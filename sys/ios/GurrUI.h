// UIKit adaptation of Gurr ForkFront's 2020 command-panel syntax and preferences.
// Reference: cd2aff11bd6c0af9f0504232647f9ae611dcfb29 (see GURR-UI.md).
static NSString *const NHDefaultPanel = @"menu ... # 20s . : ; , e d r z Z q t f w x i E Q P R W T o ^d ^p a A ^t D F p ^x ^o ?";
static id NHPref(NSString *key, id fallback) {
    return [NSUserDefaults.standardUserDefaults objectForKey:[@"gurr." stringByAppendingString:key]] ?: fallback;
}
static void NHSetPref(NSString *key,id value) {
    [NSUserDefaults.standardUserDefaults setObject:value forKey:[@"gurr." stringByAppendingString:key]];
}
static NSArray<NSArray<NSString *> *> *NHParsePanel(NSString *text) {
    NSMutableArray *result=[NSMutableArray new]; NSMutableString *part=[NSMutableString new];
    NSString *command=nil; BOOL escaped=NO;
    for(NSUInteger i=0;i<=text.length;i++) {
        unichar c=i<text.length?[text characterAtIndex:i]:' ';
        if(escaped) { [part appendFormat:@"%C",c]; escaped=NO; }
        else if(c=='\\') escaped=YES;
        else if(c=='|' && !command) { command=[part copy]; [part setString:@""]; }
        else if(c==' ') { if(command.length||part.length) [result addObject:@[command ?: [part copy],command ? [part copy] : @""]]; command=nil; [part setString:@""]; }
        else [part appendFormat:@"%C",c];
    }
    return result;
}
static NSArray<NSNumber *> *NHCommandKeys(NSString *command) {
    NSMutableArray *keys=[NSMutableArray new];
    for(NSUInteger i=0;i<command.length;i++) {
        int c=[command characterAtIndex:i];
        if(c=='^' && i+1<command.length) c=[command characterAtIndex:++i]&31;
        else if(c=='M' && i+2<command.length && [command characterAtIndex:i+1]=='-') { i+=2; c=[command characterAtIndex:i]|128; }
        else if(c=='\\' && i+1<command.length) { int n=[command characterAtIndex:i+1]; if(n=='e'||n=='n'||n=='b') { i++; c=n=='e'?27:n=='n'?10:127; } }
        [keys addObject:@(c)];
    }
    return keys;
}
@interface NHCommandButton : UIButton
@property NSString *command;
@end
@implementation NHCommandButton
@end

// Data-driven preference screens. Every setting is local to this iOS frontend.
@interface NHPreferences : UITableViewController
@property NSArray<NSDictionary *> *rows;
@property(copy) void (^changed)(void);
@end
@implementation NHPreferences
- (void)viewDidLoad {
    [super viewDidLoad]; self.overrideUserInterfaceStyle=UIUserInterfaceStyleDark;
    self.navigationItem.rightBarButtonItem=[[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemDone target:self action:@selector(close)];
}
- (void)close { [self dismissViewControllerAnimated:YES completion:self.changed]; }
- (NSInteger)tableView:(UITableView *)t numberOfRowsInSection:(NSInteger)s { return self.rows.count; }
- (UITableViewCell *)tableView:(UITableView *)t cellForRowAtIndexPath:(NSIndexPath *)p {
    NSDictionary *r=self.rows[p.row]; UITableViewCell *c=[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil];
    c.textLabel.text=r[@"title"]; c.textLabel.numberOfLines=0; c.detailTextLabel.numberOfLines=2;
    if(r[@"rows"]) c.accessoryType=UITableViewCellAccessoryDisclosureIndicator;
    else {
        id value=NHPref(r[@"key"],r[@"default"]);
        if([r[@"type"] isEqual:@"bool"]) { UISwitch *sw=[UISwitch new]; sw.on=[value boolValue]; sw.tag=p.row; [sw addTarget:self action:@selector(toggle:) forControlEvents:UIControlEventValueChanged]; c.accessoryView=sw; }
        else if(r[@"options"]) { NSInteger n=[value integerValue]; NSArray *opts=r[@"options"]; c.detailTextLabel.text=n>=0&&n<opts.count?opts[n]:@""; }
        else c.detailTextLabel.text=[value description];
    }
    return c;
}
- (void)toggle:(UISwitch *)sw { NHSetPref(self.rows[sw.tag][@"key"],@(sw.on)); if(self.changed)self.changed(); }
- (void)tableView:(UITableView *)t didSelectRowAtIndexPath:(NSIndexPath *)p {
    [t deselectRowAtIndexPath:p animated:YES]; NSDictionary *r=self.rows[p.row];
    if(r[@"rows"]) { NHPreferences *next=[[NHPreferences alloc] initWithStyle:UITableViewStyleInsetGrouped]; next.title=r[@"title"]; next.rows=r[@"rows"]; next.changed=self.changed; [self.navigationController pushViewController:next animated:YES]; return; }
    if([r[@"type"] isEqual:@"bool"])return;
    NSArray *opts=r[@"options"];
    UIAlertController *a=[UIAlertController alertControllerWithTitle:r[@"title"] message:r[@"help"] preferredStyle:opts?UIAlertControllerStyleActionSheet:UIAlertControllerStyleAlert];
    if(opts) {
        for(NSUInteger i=0;i<opts.count;i++) [a addAction:[UIAlertAction actionWithTitle:opts[i] style:UIAlertActionStyleDefault handler:^(UIAlertAction *action){ NHSetPref(r[@"key"],@(i)); [t reloadData]; if(self.changed)self.changed(); }]];
    } else {
        [a addTextFieldWithConfigurationHandler:^(UITextField *f){ f.text=[NHPref(r[@"key"],r[@"default"]) description]; f.autocapitalizationType=UITextAutocapitalizationTypeNone; f.autocorrectionType=UITextAutocorrectionTypeNo; if([r[@"type"] isEqual:@"number"])f.keyboardType=UIKeyboardTypeNumbersAndPunctuation; }];
        [a addAction:[UIAlertAction actionWithTitle:@"Save" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action){ NSString *value=a.textFields.firstObject.text ?: @""; if([r[@"type"] isEqual:@"number"]) NHSetPref(r[@"key"],@(MAX([r[@"min"] doubleValue],MIN([r[@"max"] doubleValue],value.doubleValue)))); else NHSetPref(r[@"key"],value); [t reloadData]; if(self.changed)self.changed(); }]];
    }
    [a addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    a.popoverPresentationController.sourceView=[t cellForRowAtIndexPath:p]; a.popoverPresentationController.sourceRect=[t cellForRowAtIndexPath:p].bounds;
    [self presentViewController:a animated:YES completion:nil];
}
@end
static NSDictionary *NHBool(NSString *title,NSString *key,BOOL value) { return @{@"title":title,@"key":key,@"type":@"bool",@"default":@(value)}; }
static NSDictionary *NHChoice(NSString *title,NSString *key,NSArray *options,int value) { return @{@"title":title,@"key":key,@"options":options,@"default":@(value)}; }
static NSDictionary *NHNumber(NSString *title,NSString *key,int value,int min,int max) { return @{@"title":title,@"key":key,@"type":@"number",@"default":@(value),@"min":@(min),@"max":@(max)}; }
