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

// ForkFront draws these dialogs inside the game surface. Use the same custom
// card for prompts, response questions, and short informational dialogs.
@interface NHGurrOverlay : UIView <UITextFieldDelegate>
@property (nonatomic,readonly) UITextField *inputField;
@property (nonatomic,copy) BOOL (^hardwareKeyHandler)(unichar key);
@property (nonatomic,copy) void (^onDismiss)(void);
@property (nonatomic,copy) void (^onInputReturn)(void);
@property (nonatomic,copy) void (^onInputEscape)(void);
- (instancetype)initWithTitle:(NSString *)title;
- (UILabel *)addMessage:(NSString *)message;
- (UITextField *)addInputWithInitialText:(NSString *)text keyboardType:(UIKeyboardType)keyboardType maxLength:(NSUInteger)maxLength;
- (void)addHistoryItems:(NSArray<NSString *> *)items select:(void (^)(NSString *value))select;
- (void)addTextView:(NSString *)text height:(CGFloat)height;
- (NSArray<UIButton *> *)addChoiceButtons:(NSArray<NSString *> *)choices defaultIndex:(NSUInteger)defaultIndex select:(void (^)(NSUInteger index))select;
- (void)addOptionList:(NSArray<NSString *> *)options select:(void (^)(NSUInteger index))select;
- (UIButton *)addActionWithTitle:(NSString *)title primary:(BOOL)primary handler:(void (^)(void))handler;
- (void)presentInView:(UIView *)host focusInput:(BOOL)focusInput;
- (void)dismiss;
@end

@interface NHGurrInputField : UITextField
@property (nonatomic,copy) void (^onEscape)(void);
@end
@implementation NHGurrInputField
- (void)pressesBegan:(NSSet<UIPress *> *)presses withEvent:(UIPressesEvent *)event {
    if (@available(iOS 13.4,*)) for (UIPress *press in presses) {
        NSString *characters=press.key.characters; if(!characters.length)characters=press.key.charactersIgnoringModifiers;
        if(characters.length && [characters characterAtIndex:0]==27 && self.onEscape) { self.onEscape(); return; }
    }
    [super pressesBegan:presses withEvent:event];
}
@end

@implementation NHGurrOverlay {
    UIView *_card;
    UIStackView *_content;
    UIStackView *_actions;
    NSLayoutConstraint *_centerY;
    NSLayoutConstraint *_historyHeight;
    NSLayoutConstraint *_inputTrailing;
    UIScrollView *_historyScroll;
    UITextField *_inputField;
    NSUInteger _maxLength;
    id _keyboardObserver;
    BOOL _finished;
}
- (instancetype)initWithTitle:(NSString *)title {
    if ((self=[super initWithFrame:CGRectZero])) {
        self.translatesAutoresizingMaskIntoConstraints=NO;
        self.backgroundColor=[UIColor colorWithWhite:0 alpha:0.68];
        self.accessibilityIdentifier=@"gurr.modal.overlay";
        _card=[UIView new]; _card.translatesAutoresizingMaskIntoConstraints=NO;
        _card.backgroundColor=[UIColor colorWithWhite:0.12 alpha:1];
        _card.layer.cornerRadius=5; _card.layer.borderWidth=1;
        _card.layer.borderColor=[UIColor colorWithWhite:0.42 alpha:1].CGColor;
        [self addSubview:_card];
        _content=[UIStackView new]; _content.translatesAutoresizingMaskIntoConstraints=NO;
        _content.axis=UILayoutConstraintAxisVertical; _content.spacing=12;
        [_card addSubview:_content];

        UILabel *heading=[UILabel new]; heading.text=title; heading.textColor=UIColor.whiteColor;
        heading.font=[UIFont systemFontOfSize:17 weight:UIFontWeightSemibold]; heading.numberOfLines=0;
        heading.accessibilityIdentifier=@"gurr.modal.title"; [_content addArrangedSubview:heading];
        UIView *divider=[UIView new]; divider.backgroundColor=[UIColor colorWithWhite:0.4 alpha:1];
        [divider.heightAnchor constraintEqualToConstant:1].active=YES; [_content addArrangedSubview:divider];
        _actions=[UIStackView new]; _actions.translatesAutoresizingMaskIntoConstraints=NO;
        _actions.axis=UILayoutConstraintAxisHorizontal; _actions.spacing=10;
        _actions.distribution=UIStackViewDistributionFillEqually; [_content addArrangedSubview:_actions];

        _centerY=[_card.centerYAnchor constraintEqualToAnchor:self.safeAreaLayoutGuide.centerYAnchor];
        NSLayoutConstraint *preferredWidth=[_card.widthAnchor constraintEqualToAnchor:self.widthAnchor multiplier:0.9]; preferredWidth.priority=UILayoutPriorityDefaultHigh;
        [NSLayoutConstraint activateConstraints:@[
            [_card.centerXAnchor constraintEqualToAnchor:self.centerXAnchor],
            [_card.widthAnchor constraintLessThanOrEqualToConstant:440],
            preferredWidth,
            [_card.leadingAnchor constraintGreaterThanOrEqualToAnchor:self.leadingAnchor constant:18],
            [_card.trailingAnchor constraintLessThanOrEqualToAnchor:self.trailingAnchor constant:-18],
            [_card.topAnchor constraintGreaterThanOrEqualToAnchor:self.safeAreaLayoutGuide.topAnchor constant:10],
            [_card.bottomAnchor constraintLessThanOrEqualToAnchor:self.safeAreaLayoutGuide.bottomAnchor constant:-10],
            [_content.topAnchor constraintEqualToAnchor:_card.topAnchor constant:15],
            [_content.bottomAnchor constraintEqualToAnchor:_card.bottomAnchor constant:-15],
            [_content.leadingAnchor constraintEqualToAnchor:_card.leadingAnchor constant:16],
            [_content.trailingAnchor constraintEqualToAnchor:_card.trailingAnchor constant:-16], _centerY
        ]];
        _historyScroll=[UIScrollView new]; _historyScroll.translatesAutoresizingMaskIntoConstraints=NO; _historyScroll.hidden=YES;
        _historyHeight=[_historyScroll.heightAnchor constraintEqualToConstant:0]; _historyHeight.active=YES;
    }
    return self;
}
- (UITextField *)inputField { return _inputField; }
- (void)insertContent:(UIView *)view {
    view.translatesAutoresizingMaskIntoConstraints=NO;
    [_content insertArrangedSubview:view atIndex:_content.arrangedSubviews.count-1];
}
- (UILabel *)addMessage:(NSString *)message {
    UILabel *label=[UILabel new]; label.text=message; label.textColor=[UIColor colorWithWhite:0.92 alpha:1];
    label.font=[UIFont systemFontOfSize:16]; label.numberOfLines=0; label.accessibilityIdentifier=@"gurr.modal.message";
    [self insertContent:label]; return label;
}
- (UITextField *)addInputWithInitialText:(NSString *)text keyboardType:(UIKeyboardType)keyboardType maxLength:(NSUInteger)maxLength {
    _maxLength=maxLength;
    UIView *row=[UIView new];
    _inputField=[NHGurrInputField new]; _inputField.borderStyle=UITextBorderStyleRoundedRect; _inputField.backgroundColor=UIColor.whiteColor;
    _inputField.textColor=UIColor.blackColor; _inputField.font=[UIFont systemFontOfSize:17];
    _inputField.autocapitalizationType=UITextAutocapitalizationTypeNone; _inputField.autocorrectionType=UITextAutocorrectionTypeNo;
    _inputField.spellCheckingType=UITextSpellCheckingTypeNo; _inputField.keyboardType=keyboardType;
    _inputField.returnKeyType=UIReturnKeyDone; _inputField.delegate=self; _inputField.text=text ?: @"";
    _inputField.accessibilityIdentifier=@"gurr.modal.input";
    [_inputField.heightAnchor constraintEqualToConstant:42].active=YES; [row addSubview:_inputField];
    _inputTrailing=[_inputField.trailingAnchor constraintEqualToAnchor:row.trailingAnchor];
    [NSLayoutConstraint activateConstraints:@[[ _inputField.leadingAnchor constraintEqualToAnchor:row.leadingAnchor],[_inputField.topAnchor constraintEqualToAnchor:row.topAnchor],[_inputField.bottomAnchor constraintEqualToAnchor:row.bottomAnchor],_inputTrailing]];
    [self insertContent:row]; return _inputField;
}
- (UIButton *)styledButton:(NSString *)title primary:(BOOL)primary {
    UIButton *button=[UIButton buttonWithType:UIButtonTypeCustom]; button.translatesAutoresizingMaskIntoConstraints=NO;
    button.backgroundColor=primary?[UIColor colorWithWhite:0.34 alpha:1]:[UIColor colorWithWhite:0.22 alpha:1];
    [button setTitle:title forState:UIControlStateNormal]; [button setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    button.titleLabel.font=[UIFont systemFontOfSize:16 weight:primary?UIFontWeightSemibold:UIFontWeightRegular];
    button.titleLabel.numberOfLines=2; button.layer.cornerRadius=3;
    button.layer.borderWidth=0.5; button.layer.borderColor=[UIColor colorWithWhite:0.48 alpha:1].CGColor;
    [button.heightAnchor constraintGreaterThanOrEqualToConstant:42].active=YES; return button;
}
- (UIButton *)addActionWithTitle:(NSString *)title primary:(BOOL)primary handler:(void (^)(void))handler {
    UIButton *button=[self styledButton:title primary:primary];
    button.tag=1000+_actions.arrangedSubviews.count;
    [button addAction:[UIAction actionWithHandler:^(__kindof UIAction *action){ if(handler)handler(); }] forControlEvents:UIControlEventTouchUpInside];
    [_actions addArrangedSubview:button]; return button;
}
- (void)addHistoryItems:(NSArray<NSString *> *)items select:(void (^)(NSString *))select {
    if (!items.count || !_inputField) return;
    UIButton *toggle=[UIButton buttonWithType:UIButtonTypeSystem]; [toggle setTitle:@"History" forState:UIControlStateNormal];
    toggle.translatesAutoresizingMaskIntoConstraints=NO; [toggle setTitleColor:UIColor.whiteColor forState:UIControlStateNormal]; toggle.backgroundColor=[UIColor colorWithWhite:0.24 alpha:1];
    toggle.layer.cornerRadius=3; [toggle.widthAnchor constraintGreaterThanOrEqualToConstant:74].active=YES;
    UIView *row=_inputField.superview; [row addSubview:toggle]; _inputTrailing.active=NO;
    [NSLayoutConstraint activateConstraints:@[
        [toggle.topAnchor constraintEqualToAnchor:row.topAnchor], [toggle.bottomAnchor constraintEqualToAnchor:row.bottomAnchor],
        [toggle.trailingAnchor constraintEqualToAnchor:row.trailingAnchor], [_inputField.trailingAnchor constraintEqualToAnchor:toggle.leadingAnchor constant:-8]
    ]];
    UIStackView *list=[UIStackView new]; list.axis=UILayoutConstraintAxisVertical; list.spacing=5; list.translatesAutoresizingMaskIntoConstraints=NO;
    __weak NHGurrOverlay *weakSelf=self;
    for (NSString *value in items) {
        UIButton *entry=[self styledButton:value primary:NO]; entry.contentHorizontalAlignment=UIControlContentHorizontalAlignmentLeft;
        entry.titleLabel.lineBreakMode=NSLineBreakByTruncatingTail; NSString *item=[value copy];
        [entry addAction:[UIAction actionWithHandler:^(__kindof UIAction *action){
            weakSelf.inputField.text=item; [weakSelf.inputField selectAll:nil];
            weakSelf->_historyScroll.hidden=YES; weakSelf->_historyHeight.constant=0; if(select)select(item);
        }] forControlEvents:UIControlEventTouchUpInside];
        [list addArrangedSubview:entry];
    }
    [_historyScroll addSubview:list];
    [NSLayoutConstraint activateConstraints:@[
        [list.topAnchor constraintEqualToAnchor:_historyScroll.contentLayoutGuide.topAnchor],
        [list.bottomAnchor constraintEqualToAnchor:_historyScroll.contentLayoutGuide.bottomAnchor],
        [list.leadingAnchor constraintEqualToAnchor:_historyScroll.contentLayoutGuide.leadingAnchor],
        [list.trailingAnchor constraintEqualToAnchor:_historyScroll.contentLayoutGuide.trailingAnchor],
        [list.widthAnchor constraintEqualToAnchor:_historyScroll.frameLayoutGuide.widthAnchor]
    ]];
    [self insertContent:_historyScroll];
    [toggle addAction:[UIAction actionWithHandler:^(__kindof UIAction *action){
        weakSelf->_historyScroll.hidden=!weakSelf->_historyScroll.hidden;
        weakSelf->_historyHeight.constant=weakSelf->_historyScroll.hidden?0:MIN(160,items.count*47.0);
        [weakSelf layoutIfNeeded];
    }] forControlEvents:UIControlEventTouchUpInside];
}
- (void)addTextView:(NSString *)text height:(CGFloat)height {
    UITextView *view=[UITextView new]; view.editable=NO; view.selectable=YES; view.scrollEnabled=YES;
    view.backgroundColor=UIColor.clearColor; view.textColor=[UIColor colorWithWhite:0.92 alpha:1];
    view.font=[UIFont systemFontOfSize:16]; view.text=text ?: @""; view.textContainerInset=UIEdgeInsetsMake(4,0,4,0);
    view.accessibilityIdentifier=@"gurr.modal.text";
    [view.heightAnchor constraintEqualToConstant:height].active=YES; [self insertContent:view];
}
- (NSArray<UIButton *> *)addChoiceButtons:(NSArray<NSString *> *)choices defaultIndex:(NSUInteger)defaultIndex select:(void (^)(NSUInteger))select {
    NSMutableArray<UIButton *> *buttons=[NSMutableArray new];
    for (NSUInteger start=0;start<choices.count;start+=4) {
        UIStackView *row=[UIStackView new]; row.axis=UILayoutConstraintAxisHorizontal; row.spacing=8; row.distribution=UIStackViewDistributionFillEqually;
        NSUInteger end=MIN(start+4,choices.count);
        for (NSUInteger i=start;i<end;i++) {
            UIButton *button=[self styledButton:choices.count==1?@"OK":choices[i] primary:i==defaultIndex];
            button.tag=2000+i;
            [button addAction:[UIAction actionWithHandler:^(__kindof UIAction *action){ if(select)select(i); }] forControlEvents:UIControlEventTouchUpInside];
            if (i==defaultIndex) button.accessibilityIdentifier=@"gurr.modal.choice.default";
            [row addArrangedSubview:button]; [buttons addObject:button];
        }
        [self insertContent:row];
    }
    return buttons;
}
- (void)addOptionList:(NSArray<NSString *> *)options select:(void (^)(NSUInteger))select {
    UIScrollView *scroll=[UIScrollView new]; scroll.translatesAutoresizingMaskIntoConstraints=NO;
    UIStackView *list=[UIStackView new]; list.axis=UILayoutConstraintAxisVertical; list.spacing=6; list.translatesAutoresizingMaskIntoConstraints=NO;
    for (NSUInteger i=0;i<options.count;i++) {
        UIButton *button=[self styledButton:options[i] primary:NO]; button.contentHorizontalAlignment=UIControlContentHorizontalAlignmentLeft;
        [button addAction:[UIAction actionWithHandler:^(__kindof UIAction *action){ if(select)select(i); }] forControlEvents:UIControlEventTouchUpInside];
        [list addArrangedSubview:button];
    }
    [scroll addSubview:list];
    [NSLayoutConstraint activateConstraints:@[
        [list.topAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.topAnchor], [list.bottomAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.bottomAnchor],
        [list.leadingAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.leadingAnchor], [list.trailingAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.trailingAnchor],
        [list.widthAnchor constraintEqualToAnchor:scroll.frameLayoutGuide.widthAnchor], [scroll.heightAnchor constraintEqualToConstant:MIN(300,MAX(48,options.count*48.0))]
    ]];
    [self insertContent:scroll];
}
- (void)presentInView:(UIView *)host focusInput:(BOOL)focusInput {
    [host addSubview:self];
    [NSLayoutConstraint activateConstraints:@[
        [self.topAnchor constraintEqualToAnchor:host.topAnchor], [self.bottomAnchor constraintEqualToAnchor:host.bottomAnchor],
        [self.leadingAnchor constraintEqualToAnchor:host.leadingAnchor], [self.trailingAnchor constraintEqualToAnchor:host.trailingAnchor]
    ]];
    [host layoutIfNeeded];
    if (_inputField && focusInput) dispatch_async(dispatch_get_main_queue(),^{ [self->_inputField becomeFirstResponder]; [self->_inputField selectAll:nil]; });
    else { if(_inputField)dispatch_async(dispatch_get_main_queue(),^{ [self->_inputField selectAll:nil]; }); [self becomeFirstResponder]; }
}
- (void)dismiss {
    if (_finished) return; _finished=YES;
    [_inputField resignFirstResponder]; [self resignFirstResponder];
    if (_keyboardObserver) { [NSNotificationCenter.defaultCenter removeObserver:_keyboardObserver]; _keyboardObserver=nil; }
    [self removeFromSuperview]; void (^done)(void)=self.onDismiss; self.onDismiss=nil; self.onInputReturn=nil; self.onInputEscape=nil; self.hardwareKeyHandler=nil;
    if (done) done();
}
- (BOOL)textFieldShouldReturn:(UITextField *)textField { if(self.onInputReturn)self.onInputReturn(); return YES; }
- (BOOL)textField:(UITextField *)textField shouldChangeCharactersInRange:(NSRange)range replacementString:(NSString *)string {
    if (!_maxLength || !string.length) return YES;
    NSString *next=[textField.text stringByReplacingCharactersInRange:range withString:string]; return next.length<=_maxLength;
}
- (BOOL)canBecomeFirstResponder { return YES; }
- (void)pressesBegan:(NSSet<UIPress *> *)presses withEvent:(UIPressesEvent *)event {
    if (@available(iOS 13.4,*)) {
        for (UIPress *press in presses) {
            NSString *characters=press.key.characters;
            if (!characters.length) characters=press.key.charactersIgnoringModifiers;
            if (characters.length && self.hardwareKeyHandler && self.hardwareKeyHandler([characters characterAtIndex:0])) return;
        }
    }
    [super pressesBegan:presses withEvent:event];
}
- (void)didMoveToSuperview {
    [super didMoveToSuperview]; if(!self.superview || _keyboardObserver)return;
    __weak NHGurrOverlay *weakSelf=self;
    _keyboardObserver=[NSNotificationCenter.defaultCenter addObserverForName:UIKeyboardWillChangeFrameNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *note){
        NHGurrOverlay *strongSelf=weakSelf; if(!strongSelf.superview)return;
        CGRect frame=[note.userInfo[UIKeyboardFrameEndUserInfoKey] CGRectValue]; CGRect local=[strongSelf convertRect:frame fromView:nil];
        CGFloat overlap=MAX(0,CGRectGetMaxY(strongSelf.bounds)-CGRectGetMinY(local));
        strongSelf->_centerY.constant=-MAX(0,overlap-strongSelf.safeAreaInsets.bottom)/2;
        NSTimeInterval duration=[note.userInfo[UIKeyboardAnimationDurationUserInfoKey] doubleValue];
        [UIView animateWithDuration:duration animations:^{ [strongSelf layoutIfNeeded]; }];
    }];
}
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
    NHGurrOverlay *dialog=[[NHGurrOverlay alloc] initWithTitle:r[@"title"]];
    if(r[@"help"]) [dialog addMessage:r[@"help"]];
    __weak NHPreferences *weakSelf=self; __weak NHGurrOverlay *weakDialog=dialog;
    if(opts) {
        [dialog addOptionList:opts select:^(NSUInteger index){
            NHSetPref(r[@"key"],@(index)); [weakDialog dismiss]; [t reloadData]; if(weakSelf.changed)weakSelf.changed();
        }];
    } else {
        UITextField *field=[dialog addInputWithInitialText:[NHPref(r[@"key"],r[@"default"]) description] keyboardType:[r[@"type"] isEqual:@"number"]?UIKeyboardTypeNumbersAndPunctuation:UIKeyboardTypeDefault maxLength:128];
        __weak UITextField *weakField=field;
        void (^save)(void)=^{
            NSString *value=weakField.text ?: @"";
            if([r[@"type"] isEqual:@"number"]) NHSetPref(r[@"key"],@(MAX([r[@"min"] doubleValue],MIN([r[@"max"] doubleValue],value.doubleValue))));
            else NHSetPref(r[@"key"],value);
            [weakDialog dismiss]; [t reloadData]; if(weakSelf.changed)weakSelf.changed();
        };
        dialog.onInputReturn=save;
        dialog.onInputEscape=^{ [weakDialog dismiss]; };
        ((NHGurrInputField *)field).onEscape=^{ [weakDialog dismiss]; };
        [dialog addActionWithTitle:@"Cancel" primary:NO handler:^{ [weakDialog dismiss]; }];
        [dialog addActionWithTitle:@"Save" primary:YES handler:save];
    }
    if(opts) [dialog addActionWithTitle:@"Cancel" primary:NO handler:^{ [weakDialog dismiss]; }];
    [dialog presentInView:self.view focusInput:YES];
}
@end
static NSDictionary *NHBool(NSString *title,NSString *key,BOOL value) { return @{@"title":title,@"key":key,@"type":@"bool",@"default":@(value)}; }
static NSDictionary *NHChoice(NSString *title,NSString *key,NSArray *options,int value) { return @{@"title":title,@"key":key,@"options":options,@"default":@(value)}; }
static NSDictionary *NHNumber(NSString *title,NSString *key,int value,int min,int max) { return @{@"title":title,@"key":key,@"type":@"number",@"default":@(value),@"min":@(min),@"max":@(max)}; }
