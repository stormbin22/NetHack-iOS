#import <UIKit/UIKit.h>
#import "Bridge.h"

static UIColor *NHColor(int rgb) {
    return [UIColor colorWithRed:((rgb>>16)&255)/255.0 green:((rgb>>8)&255)/255.0 blue:(rgb&255)/255.0 alpha:1];
}
@interface NHMap : UIView
@property NSMutableDictionary<NSNumber *,NSArray *> *cells;
@property UIImage *tiles;
@property CGPoint cursor;
@end
@implementation NHMap
- (instancetype)init {
    if ((self=[super initWithFrame:CGRectMake(0,0,80*24,21*24)])) {
        self.cells=[NSMutableDictionary new]; self.backgroundColor=UIColor.blackColor;
        self.tiles=[UIImage imageWithContentsOfFile:[NSBundle.mainBundle pathForResource:@"default_16x16" ofType:@"png"]];
        self.cursor=CGPointMake(-1,-1);
    } return self;
}
- (void)drawRect:(CGRect)rect {
    CGContextRef ctx=UIGraphicsGetCurrentContext(); CGContextSetInterpolationQuality(ctx,kCGInterpolationNone);
    for (NSNumber *key in self.cells) {
        int k=key.intValue; CGRect r=CGRectMake((k%80)*24,(k/80)*24,24,24);
        if (!CGRectIntersectsRect(rect,r)) continue;
        NSArray *v=self.cells[key]; int tile=[v[0] intValue];
        int cols=(int)self.tiles.size.width/16, rows=(int)self.tiles.size.height/16;
        if (cols>0 && tile>=0 && tile<cols*rows) {
            CGImageRef crop=CGImageCreateWithImageInRect(self.tiles.CGImage,CGRectMake((tile%cols)*16,(tile/cols)*16,16,16));
            [[UIImage imageWithCGImage:crop] drawInRect:r]; CGImageRelease(crop);
        } else {
            unichar c=[v[1] intValue]; [[NSString stringWithCharacters:&c length:1] drawInRect:r withAttributes:@{
                NSFontAttributeName:[UIFont monospacedSystemFontOfSize:21 weight:UIFontWeightRegular],NSForegroundColorAttributeName:NHColor([v[2] intValue])}];
        }
    }
    if(self.cursor.x>=0) {
        [UIColor.yellowColor setStroke]; CGContextSetLineWidth(ctx,1);
        CGContextStrokeRect(ctx,CGRectMake(self.cursor.x*24+1,self.cursor.y*24+1,22,22));
    }
}
@end

@interface NHMenu : UITableViewController
@property NSArray<NSDictionary *> *items;
@property NSMutableDictionary<NSNumber *,NSNumber *> *selection;
@property int how;
@property(copy) void (^finish)(id);
@end
@implementation NHMenu
- (void)viewDidLoad {
    [super viewDidLoad]; self.selection=[NSMutableDictionary new];
    for(NSDictionary *item in self.items) if([item[@"selected"] boolValue] && [item[@"id"] longLongValue]) self.selection[item[@"id"]]=@(-1);
    self.navigationItem.leftBarButtonItem=[[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemCancel target:self action:@selector(cancel)];
    self.navigationItem.rightBarButtonItem=[[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemDone target:self action:@selector(done)];
    self.tableView.allowsMultipleSelection=self.how==2;
}
- (void)complete:(id)value { void (^callback)(id)=self.finish; self.finish=nil; [self dismissViewControllerAnimated:YES completion:^{ if(callback)callback(value); }]; }
- (void)cancel { [self complete:nil]; }
- (void)done {
    NHBuffer *b=[NHBuffer count:self.selection.count*2 size:sizeof(jlong)]; jlong *p=b.data.mutableBytes;
    // Preserve original menu order, including preselected entries.
    for(NSDictionary *item in self.items) if(self.selection[item[@"id"]]) { *p++=[item[@"id"] longLongValue]; *p++=[self.selection[item[@"id"]] longLongValue]; }
    [self complete:b];
}
- (NSInteger)tableView:(UITableView *)t numberOfRowsInSection:(NSInteger)s { return self.items.count; }
- (UITableViewCell *)tableView:(UITableView *)t cellForRowAtIndexPath:(NSIndexPath *)p {
    UITableViewCell *c=[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil];
    NSDictionary *item=self.items[p.row]; c.textLabel.text=item[@"text"]; c.textLabel.numberOfLines=0;
    c.textLabel.font=[UIFont monospacedSystemFontOfSize:15 weight:UIFontWeightRegular];
    c.accessoryType=self.selection[item[@"id"]] ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone;
    c.selectionStyle=[item[@"id"] longLongValue] && self.how ? UITableViewCellSelectionStyleDefault : UITableViewCellSelectionStyleNone;
    return c;
}
- (void)tableView:(UITableView *)t didSelectRowAtIndexPath:(NSIndexPath *)p {
    NSDictionary *item=self.items[p.row]; NSNumber *ident=item[@"id"];
    if(!self.how || !ident.longLongValue)return;
    if(self.how==1) { [self.selection removeAllObjects]; self.selection[ident]=@(-1); [self done]; }
    else { if(self.selection[ident]) [self.selection removeObjectForKey:ident]; else self.selection[ident]=@(-1); [t reloadData]; }
}
@end

@interface NHGame : UIViewController <UIScrollViewDelegate,UITextFieldDelegate>
@property NHMap *map;
@property UIScrollView *scroll;
@property UITextView *messages;
@property UILabel *status;
@property UITextField *keyboard;
@property NSMutableDictionary<NSNumber *,NSMutableDictionary *> *windows;
@property NSCondition *inputCondition;
@property NSMutableArray<NSArray *> *input;
@property int nextWindow;
@property BOOL started, ended, positionInput, numpad;
@property BOOL saveRequested, mouseLocked, expectsDirection, panned;
@property CGPoint player;
@property UIBackgroundTaskIdentifier backgroundTask;
- (void)enqueue:(NSArray *)event;
- (id)invoke:(NSString *)name arguments:(NSArray *)args;
@end
static NHGame *game;
@implementation NHGame
- (void)viewDidLoad {
    [super viewDidLoad]; self.view.backgroundColor=UIColor.blackColor; self.overrideUserInterfaceStyle=UIUserInterfaceStyleDark;
    self.windows=[NSMutableDictionary new]; self.inputCondition=[NSCondition new]; self.input=[NSMutableArray new]; self.backgroundTask=UIBackgroundTaskInvalid;
    UIStackView *stack=[UIStackView new]; stack.axis=UILayoutConstraintAxisVertical; stack.spacing=4; stack.translatesAutoresizingMaskIntoConstraints=NO;
    [self.view addSubview:stack]; UILayoutGuide *safe=self.view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[[stack.leadingAnchor constraintEqualToAnchor:safe.leadingAnchor], [stack.trailingAnchor constraintEqualToAnchor:safe.trailingAnchor], [stack.topAnchor constraintEqualToAnchor:safe.topAnchor], [stack.bottomAnchor constraintEqualToAnchor:self.view.keyboardLayoutGuide.topAnchor]]];
    self.messages=[UITextView new]; self.messages.editable=NO; self.messages.font=[UIFont monospacedSystemFontOfSize:13 weight:UIFontWeightRegular];
    [self.messages.heightAnchor constraintEqualToConstant:88].active=YES; [stack addArrangedSubview:self.messages];
    self.status=[UILabel new]; self.status.numberOfLines=3; self.status.textColor=UIColor.greenColor; self.status.font=[UIFont monospacedSystemFontOfSize:12 weight:UIFontWeightRegular]; [stack addArrangedSubview:self.status];
    self.map=[NHMap new]; self.scroll=[UIScrollView new]; self.scroll.delegate=self; self.scroll.minimumZoomScale=0.4; self.scroll.maximumZoomScale=3;
    self.scroll.contentSize=self.map.bounds.size; [self.scroll addSubview:self.map]; [stack addArrangedSubview:self.scroll];
    UITapGestureRecognizer *tap=[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(mapTap:)]; [self.map addGestureRecognizer:tap];
    UILongPressGestureRecognizer *hold=[[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(mapHold:)]; [self.map addGestureRecognizer:hold]; [tap requireGestureRecognizerToFail:hold];
    NSArray *rows=@[@[@"↖",@"↑",@"↗",@"i",@",",@"Save"],@[@"←",@"·",@"→",@"o",@"s",@"Keys"],@[@"↙",@"↓",@"↘",@"<",@">",@"Esc"],@[@"y",@"n",@"Enter",@"Space",@"#",@"?"]];
    for(NSArray *row in rows) {
        UIStackView *bar=[UIStackView new]; bar.distribution=UIStackViewDistributionFillEqually; bar.spacing=3;
        for(NSString *title in row) { UIButton *b=[UIButton buttonWithType:UIButtonTypeSystem]; [b setTitle:title forState:UIControlStateNormal]; b.backgroundColor=[UIColor colorWithWhite:0.12 alpha:1]; [b addTarget:self action:@selector(key:) forControlEvents:UIControlEventTouchUpInside]; [bar addArrangedSubview:b]; }
        [bar.heightAnchor constraintEqualToConstant:36].active=YES; [stack addArrangedSubview:bar];
    }
    self.keyboard=[UITextField new]; self.keyboard.delegate=self; self.keyboard.autocorrectionType=UITextAutocorrectionTypeNo; self.keyboard.autocapitalizationType=UITextAutocapitalizationTypeNone; self.keyboard.keyboardType=UIKeyboardTypeASCIICapable; self.keyboard.placeholder=@"명령 키 입력"; self.keyboard.textColor=UIColor.whiteColor; [self.keyboard.heightAnchor constraintEqualToConstant:28].active=YES; [stack addArrangedSubview:self.keyboard];
}
- (UIView *)viewForZoomingInScrollView:(UIScrollView *)scroll { return self.map; }
- (void)scrollViewWillBeginDragging:(UIScrollView *)scroll { self.panned=YES; }
- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated]; if(self.started)return; self.started=YES;
    NSURL *docs=[NSFileManager.defaultManager URLsForDirectory:NSDocumentDirectory inDomains:NSUserDomainMask].firstObject;
    NSURL *dir=[docs URLByAppendingPathComponent:@"NetHack" isDirectory:YES]; NSError *error=nil;
    [NSFileManager.defaultManager createDirectoryAtURL:dir withIntermediateDirectories:YES attributes:nil error:&error];
    NSURL *assets=[NSBundle.mainBundle URLForResource:@"GameData" withExtension:nil];
    for(NSURL *source in [NSFileManager.defaultManager contentsOfDirectoryAtURL:assets includingPropertiesForKeys:nil options:0 error:&error]) {
        NSURL *dest=[dir URLByAppendingPathComponent:source.lastPathComponent];
        if(![NSFileManager.defaultManager fileExistsAtPath:dest.path]) [NSFileManager.defaultManager copyItemAtURL:source toURL:dest error:&error];
    }
    [NSFileManager.defaultManager createDirectoryAtURL:[dir URLByAppendingPathComponent:@"save"] withIntermediateDirectories:YES attributes:nil error:&error];
    if(error) { self.messages.text=error.localizedDescription; return; }
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED,0),^{
        NHRun(dir.path.UTF8String);
        dispatch_async(dispatch_get_main_queue(),^{ self.ended=YES; self.status.text=@"게임이 종료되었습니다. 다시 실행하려면 앱을 닫고 열어주세요."; if(self.backgroundTask!=UIBackgroundTaskInvalid) { [UIApplication.sharedApplication endBackgroundTask:self.backgroundTask]; self.backgroundTask=UIBackgroundTaskInvalid; } });
    });
}
- (void)enqueue:(NSArray *)event { [self.inputCondition lock]; if(!self.ended && self.input.count<32) [self.input addObject:event]; [self.inputCondition signal]; [self.inputCondition unlock]; }
- (void)key:(UIButton *)b {
    NSString *s=b.currentTitle;
    if([s isEqual:@"Keys"]) { [self.keyboard becomeFirstResponder]; return; }
    NSDictionary *keys=@{@"↖":@(self.numpad?'7':'y'),@"↑":@(self.numpad?'8':'k'),@"↗":@(self.numpad?'9':'u'),@"←":@(self.numpad?'4':'h'),@"·":@'.',@"→":@(self.numpad?'6':'l'),@"↙":@(self.numpad?'1':'b'),@"↓":@(self.numpad?'2':'j'),@"↘":@(self.numpad?'3':'n'),@"Esc":@27,@"Enter":@13,@"Space":@32,@"Save":@128};
    [self enqueue:@[keys[s] ?: @([s characterAtIndex:0])]];
}
- (BOOL)textField:(UITextField *)f shouldChangeCharactersInRange:(NSRange)r replacementString:(NSString *)s { for(NSUInteger i=0;i<s.length;i++) [self enqueue:@[@([s characterAtIndex:i])]]; return NO; }
- (BOOL)textFieldShouldReturn:(UITextField *)f { [self enqueue:@[@13]]; [f resignFirstResponder]; return NO; }
- (void)mapTap:(UITapGestureRecognizer *)tap { CGPoint p=[tap locationInView:self.map]; [self touch:p longPress:NO]; }
- (void)mapHold:(UILongPressGestureRecognizer *)hold { if(hold.state==UIGestureRecognizerStateBegan)[self touch:[hold locationInView:self.map] longPress:YES]; }
- (void)touch:(CGPoint)p longPress:(BOOL)hold {
    int x=(int)(p.x/24),y=(int)(p.y/24); if(x<1||x>=80||y<0||y>=21)return;
    CGFloat dx=p.x-(self.player.x+0.5)*24,dy=p.y-(self.player.y+0.5)*24;
    CGFloat z=self.scroll.zoomScale;
    BOOL onSelf=(x==(int)self.player.x && y==(int)self.player.y) || (dx*dx+dy*dy)*z*z<25*25;
    BOOL travel=self.panned && (abs(x-(int)self.player.x)>3 || abs(y-(int)self.player.y)>3);
    if(self.mouseLocked || (!self.expectsDirection && (onSelf||travel))) {
        if(onSelf && !self.mouseLocked) { x=self.player.x; y=self.player.y; }
        [self enqueue:@[@0,@(x),@(y)]];
    } else {
        int c='.';
        if(!onSelf) {
            if(fabs(dy)<(sqrt(2)-1)*fabs(dx))c=dx>0?'l':'h';
            else if(fabs(dx)<(sqrt(2)-1)*fabs(dy))c=dy<0?'k':'j';
            else c=dx>0?(dy<0?'u':'n'):(dy<0?'y':'b');
        }
        if(self.numpad) { const char *v="hjklyubn",*n="42867913"; const char *at=strchr(v,c); if(at)c=n[at-v]; }
        if(hold && !self.expectsDirection)[self enqueue:@[@'g']];
        [self enqueue:@[@(c)]];
    }
    self.panned=NO;
}
- (id)prompt:(NSString *)title initial:(NSString *)initial {
    dispatch_semaphore_t ready=dispatch_semaphore_create(0); __block NSString *answer=nil;
    dispatch_async(dispatch_get_main_queue(),^{
        [self.keyboard resignFirstResponder];
        UIAlertController *alert=[UIAlertController alertControllerWithTitle:title message:nil preferredStyle:UIAlertControllerStyleAlert];
        [alert addTextFieldWithConfigurationHandler:^(UITextField *f){ f.text=initial; f.autocapitalizationType=UITextAutocapitalizationTypeNone; f.autocorrectionType=UITextAutocorrectionTypeNo; f.keyboardType=UIKeyboardTypeASCIICapable; }];
        [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:^(UIAlertAction *a){ answer=@"\033"; dispatch_semaphore_signal(ready); }]];
        [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a){ answer=alert.textFields.firstObject.text ?: @""; dispatch_semaphore_signal(ready); }]];
        [self presentViewController:alert animated:YES completion:nil];
    }); dispatch_semaphore_wait(ready,DISPATCH_TIME_FOREVER); return answer;
}
- (id)menu:(NSNumber *)wid how:(int)how {
    dispatch_semaphore_t ready=dispatch_semaphore_create(0); __block id result=nil;
    dispatch_async(dispatch_get_main_queue(),^{
        [self.keyboard resignFirstResponder]; NSMutableDictionary *w=self.windows[wid];
        NHMenu *menu=[NHMenu new]; menu.how=how; menu.title=w[@"title"] ?: @"NetHack"; menu.items=[w[@"items"] copy];
        menu.finish=^(id value){result=value; dispatch_semaphore_signal(ready);};
        UINavigationController *nav=[[UINavigationController alloc] initWithRootViewController:menu]; nav.modalPresentationStyle=UIModalPresentationFullScreen;
        [self presentViewController:nav animated:YES completion:nil];
    }); dispatch_semaphore_wait(ready,DISPATCH_TIME_FOREVER); return result;
}
- (id)invoke:(NSString *)name arguments:(NSArray *)a {
    if([name isEqual:@"receiveKeyCmd"] || [name isEqual:@"receivePosKeyCmd"]) {
        BOOL pos=[name isEqual:@"receivePosKeyCmd"];
        dispatch_sync(dispatch_get_main_queue(),^{ self.mouseLocked=pos && [a[0] boolValue]; });
        [self.inputCondition lock];
        NSArray *event=nil;
        do { while(!self.input.count)[self.inputCondition wait]; event=self.input.firstObject; [self.input removeObjectAtIndex:0]; } while(!pos && [event[0] intValue]==0);
        [self.inputCondition unlock];
        dispatch_sync(dispatch_get_main_queue(),^{ self.expectsDirection=NO; if([event[0] intValue]==128)self.saveRequested=YES; });
        if([event[0] intValue]==0) { NHBuffer *b=a[1]; jint *p=b.data.mutableBytes; p[0]=[event[1] intValue]; p[1]=[event[2] intValue]; }
        return event[0];
    }
    if([name isEqual:@"askName"]) {
        NSString *last=[NSUserDefaults.standardUserDefaults stringForKey:@"player"] ?: @"Player";
        NSString *value=[self prompt:@"캐릭터 이름 (같은 이름으로 저장 복원)" initial:last];
        if(value.length && ![value isEqual:@"\033"]) [NSUserDefaults.standardUserDefaults setObject:value forKey:@"player"];
        return [value stringByAppendingString:@"0"];
    }
    if([name isEqual:@"getLine"])return [self prompt:NHText(a[0]) initial:@""];
    if([name isEqual:@"selectMenu"])return [self menu:a[0] how:[a[1] intValue]];
    if([name isEqual:@"getDumplogDir"])return @".";
    if([name isEqual:@"displayWindow"]) {
        __block BOOL text=NO;
        dispatch_sync(dispatch_get_main_queue(),^{ int t=[self.windows[a[0]][@"type"] intValue]; text=t==4||t==5; if(t==1 && self.saveRequested && [a[1] boolValue])[self enqueue:@[@32]]; });
        if(text) { id result=[self menu:a[0] how:0]; [self enqueue:@[@32]]; return result; }
    }
    if([name isEqual:@"delayOutput"]) { [NSThread sleepForTimeInterval:0.03]; return nil; }
    __block id result=nil;
    dispatch_sync(dispatch_get_main_queue(),^{
        if([name isEqual:@"createWindow"]) { NSNumber *wid=@(++self.nextWindow); self.windows[wid]=[@{@"type":a[0],@"items":[NSMutableArray new],@"text":[NSMutableString new]} mutableCopy]; result=wid; }
        else if([name isEqual:@"destroyWindow"]) [self.windows removeObjectForKey:a[0]];
        else if([name isEqual:@"clearWindow"] || [name isEqual:@"startMenu"]) {
            NSMutableDictionary *w=self.windows[a[0]]; w[@"items"]=[NSMutableArray new]; w[@"text"]=[NSMutableString new];
            if([w[@"type"] intValue]==3) { [self.map.cells removeAllObjects]; [self.map setNeedsDisplay]; }
            if([w[@"type"] intValue]==2) self.status.text=@"";
        }
        else if([name isEqual:@"putString"] || [name isEqual:@"rawPrint"]) {
            BOOL raw=[name isEqual:@"rawPrint"]; NSString *s=NHText(a[raw?1:2]); NSMutableDictionary *w=raw?nil:self.windows[a[0]]; int type=[w[@"type"] intValue];
            if(type==2) { NSMutableString *t=w[@"text"]; [t appendFormat:@"%@%@",[a[3] boolValue]?@"":@"\n",s]; self.status.text=t; }
            else if(type==4||type==5) [w[@"items"] addObject:@{@"id":@0,@"text":s}];
            else { NSString *t=[self.messages.text stringByAppendingFormat:@"\n%@",s]; if(t.length>12000)t=[t substringFromIndex:t.length-12000]; self.messages.text=t; [self.messages scrollRangeToVisible:NSMakeRange(t.length,0)]; }
        }
        else if([name isEqual:@"printTile"]) { int x=[a[1] intValue],y=[a[2] intValue]; self.map.cells[@(y*80+x)]=@[a[3],a[4],a[5],a[6]]; [self.map setNeedsDisplay]; }
        else if([name isEqual:@"setCursorPos"]) { if([self.windows[a[0]][@"type"] intValue]==3) { self.map.cursor=CGPointMake([a[1] intValue],[a[2] intValue]); [self.map setNeedsDisplay]; } }
        else if([name isEqual:@"cliparound"]) { self.player=CGPointMake([a[2] floatValue],[a[3] floatValue]); CGFloat z=self.scroll.zoomScale; CGPoint p=CGPointMake([a[0] floatValue]*24*z-self.scroll.bounds.size.width/2,[a[1] floatValue]*24*z-self.scroll.bounds.size.height/2); p.x=MAX(0,MIN(p.x,self.scroll.contentSize.width-self.scroll.bounds.size.width)); p.y=MAX(0,MIN(p.y,self.scroll.contentSize.height-self.scroll.bounds.size.height)); [self.scroll setContentOffset:p animated:NO]; }
        else if([name isEqual:@"addMenu"]) [self.windows[a[0]][@"items"] addObject:@{@"id":a[2],@"text":NHText(a[6]),@"selected":a[7]}];
        else if([name isEqual:@"endMenu"]) self.windows[a[0]][@"title"]=NHText(a[1]);
        else if([name isEqual:@"ynFunction"]) { self.messages.text=[self.messages.text stringByAppendingFormat:@"\n%@ [%@]",NHText(a[0]),NHText(a[1])]; [self.messages scrollRangeToVisible:NSMakeRange(self.messages.text.length,0)]; }
        else if([name isEqual:@"setNumPadOption"]) self.numpad=[a[0] boolValue];
        else if([name isEqual:@"askDirection"]) self.expectsDirection=YES;
        else if([name isEqual:@"copyText"]) UIPasteboard.generalPasteboard.string=NHText(a[0]);
        else if([name isEqual:@"debugLog"]) NSLog(@"NetHack: %@",NHText(a[0]));
    }); return result;
}
@end
id NHInvoke(NSString *name,NSArray *args) { return [game invoke:name arguments:args]; }

@interface NHApp : UIResponder <UIApplicationDelegate>
@property UIWindow *window;
@end
@implementation NHApp
- (BOOL)application:(UIApplication *)app didFinishLaunchingWithOptions:(NSDictionary *)options {
    self.window=[[UIWindow alloc] initWithFrame:UIScreen.mainScreen.bounds]; game=[NHGame new];
    self.window.rootViewController=game; [self.window makeKeyAndVisible]; return YES;
}
- (void)applicationDidEnterBackground:(UIApplication *)app {
    if(game.ended)return;
    game.backgroundTask=[app beginBackgroundTaskWithExpirationHandler:^{ if(game.backgroundTask!=UIBackgroundTaskInvalid) { [app endBackgroundTask:game.backgroundTask]; game.backgroundTask=UIBackgroundTaskInvalid; } }];
    [game enqueue:@[@128]];
}
@end
int main(int argc,char **argv) { @autoreleasepool { return UIApplicationMain(argc,argv,nil,NSStringFromClass(NHApp.class)); } }
