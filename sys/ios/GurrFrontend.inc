// Included inside NHGame's implementation; all UIKit operations run on main.
- (NHCommandButton *)button:(NSString *)title command:(NSString *)command {
    NHCommandButton *b=[NHCommandButton buttonWithType:UIButtonTypeCustom]; b.command=command;
    [b setTitle:title forState:UIControlStateNormal]; [b setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    b.titleLabel.font=[UIFont systemFontOfSize:16]; b.backgroundColor=[UIColor colorWithWhite:0.22 alpha:1];
    b.layer.cornerRadius=3; b.layer.borderWidth=0.5; b.layer.borderColor=[UIColor colorWithWhite:0.4 alpha:1].CGColor;
    [b addTarget:self action:@selector(command:) forControlEvents:UIControlEventTouchUpInside]; return b;
}
- (void)viewDidLoad {
    [super viewDidLoad]; self.view.backgroundColor=UIColor.blackColor; self.overrideUserInterfaceStyle=UIUserInterfaceStyleDark;
    self.windows=[NSMutableDictionary new]; self.inputCondition=[NSCondition new]; self.input=[NSMutableArray new]; self.backgroundTask=UIBackgroundTaskInvalid;
    self.panels=[NSMutableArray new]; self.panelDefinitions=[NSMutableArray new]; self.history=[NSMutableArray new];
    self.map=[NHMap new]; self.scroll=[UIScrollView new]; self.scroll.delegate=self; self.scroll.minimumZoomScale=0.2; self.scroll.maximumZoomScale=4;
    self.scroll.contentSize=self.map.bounds.size; [self.scroll addSubview:self.map]; [self.view addSubview:self.scroll];
    self.status=[UILabel new]; self.status.numberOfLines=2; self.status.textColor=UIColor.whiteColor; self.status.userInteractionEnabled=YES;
    self.status.font=[UIFont monospacedSystemFontOfSize:12 weight:UIFontWeightRegular]; [self.view addSubview:self.status];
    self.messages=[UITextView new]; self.messages.editable=NO; self.messages.selectable=NO; self.messages.backgroundColor=UIColor.clearColor; self.messages.textColor=UIColor.whiteColor;
    self.messages.font=[UIFont systemFontOfSize:15]; self.messages.textContainerInset=UIEdgeInsetsMake(2,0,2,0); [self.view addSubview:self.messages];
    [self.messages addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(messageTap)]];
    UILongPressGestureRecognizer *history=[[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(historyHold:)]; [self.messages addGestureRecognizer:history];
    [self.status addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(showMenu)]];
    UITapGestureRecognizer *tap=[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(mapTap:)]; [self.map addGestureRecognizer:tap];
    UILongPressGestureRecognizer *hold=[[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(mapHold:)]; [self.map addGestureRecognizer:hold]; [tap requireGestureRecognizerToFail:hold];
    self.keyboard=[UITextField new]; self.keyboard.delegate=self; // Text prompts use the system keyboard; game commands use ForkFront keys.
    self.keyboardPanel=[UIView new]; self.keyboardPanel.backgroundColor=UIColor.blackColor; self.keyboardPanel.hidden=YES; [self.view addSubview:self.keyboardPanel];
    self.dpad=[UIView new]; [self.view addSubview:self.dpad];
    self.moreButton=[self button:@"Tap to continue" command:@"continue"]; self.moreButton.hidden=YES; [self.view addSubview:self.moreButton];
    NSString *path=[NSBundle.mainBundle pathForResource:@"GurrKeyboard" ofType:@"json"];
    self.keyboardLayouts=[NSJSONSerialization JSONObjectWithData:[NSData dataWithContentsOfFile:path] options:0 error:NULL];
    self.keyboardMode=@"qwerty"; [self applyPreferences];
}
- (void)applyPreferences {
    NSString *tile=@[@"TTY",@"default_16x16",@"geoduck_15x25",@"nevanda_32x32"][[NHPref(@"tiles",@1) unsignedIntegerValue]%4];
    self.map.tiles=[UIImage imageWithContentsOfFile:[NSBundle.mainBundle pathForResource:tile ofType:@"png"]];
    self.map.tileSize=[tile hasPrefix:@"geoduck"]?CGSizeMake(15,25):[tile hasPrefix:@"nevanda"]?CGSizeMake(32,32):CGSizeMake(16,16);
    [self.map setNeedsDisplay];
    for(UIView *p in self.panels)[p removeFromSuperview]; [self.panels removeAllObjects]; [self.panelDefinitions removeAllObjects];
    BOOL landscape=self.view.bounds.size.width>self.view.bounds.size.height;
    for(int i=0;i<6;i++) {
        NSString *prefix=[NSString stringWithFormat:@"p%d.",i];
        if(![NHPref([prefix stringByAppendingString:landscape?@"land":@"port"],@(i==0)) boolValue])continue;
        NSString *commands=NHPref([prefix stringByAppendingString:@"commands"],i==0?NHDefaultPanel:@"");
        NSArray *parsed=NHParsePanel(commands); if(!parsed.count)continue;
        NSInteger loc=[NHPref([prefix stringByAppendingString:landscape?@"landLoc":@"portLoc"],@3) integerValue];
        CGFloat size=[NHPref([prefix stringByAppendingString:@"size"],@0) floatValue]; size=50+(size>0?2*size:size);
        UIScrollView *panel=[UIScrollView new]; panel.backgroundColor=UIColor.blackColor; panel.alpha=[NHPref([prefix stringByAppendingString:@"opacity"],@255) floatValue]/255.0;
        CGFloat offset=0; BOOL vertical=loc<2;
        for(NSArray *item in parsed) {
            NHCommandButton *b=[self button:[item[1] length]?item[1]:item[0] command:item[0]];
            CGFloat length=MAX(size,[b.currentTitle sizeWithAttributes:@{NSFontAttributeName:b.titleLabel.font}].width+16);
            b.frame=vertical?CGRectMake(2,offset+2,size-4,size-4):CGRectMake(offset+2,2,length-4,size-4); offset+=vertical?size:length; [panel addSubview:b];
        }
        panel.contentSize=vertical?CGSizeMake(size,offset):CGSizeMake(offset,size);
        UILongPressGestureRecognizer *edit=[[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(panelHold:)]; [panel addGestureRecognizer:edit]; panel.tag=i;
        [self.panels addObject:panel]; [self.panelDefinitions addObject:@{@"loc":@(loc),@"size":@(size)}]; [self.view addSubview:panel];
    }
    for(UIView *v in self.dpad.subviews)[v removeFromSuperview];
    NSArray *directions=self.numpad?@[@"7",@"8",@"9",@"4",@".",@"6",@"1",@"2",@"3",@"<",@"Esc",@">"]:@[@"y",@"k",@"u",@"h",@".",@"l",@"b",@"j",@"n",@"<",@"Esc",@">"];
    CGFloat ds=44+[NHPref(@"ovlSize",@0) floatValue];
    for(NSUInteger i=0;i<directions.count;i++) { NHCommandButton *b=[self button:directions[i] command:i==10?@"escape":directions[i]]; b.frame=CGRectMake((i%3)*ds+1,(i/3)*ds+1,ds-2,ds-2); [self.dpad addSubview:b]; }
    self.dpad.bounds=CGRectMake(0,0,ds*3,ds*4); self.dpad.alpha=[NHPref(@"ovlOpacity",@255) floatValue]/255;
    self.messages.font=[NHPref(@"monospace",@NO) boolValue]?[UIFont monospacedSystemFontOfSize:15 weight:UIFontWeightRegular]:[UIFont systemFontOfSize:15];
    self.status.backgroundColor=[UIColor colorWithWhite:0 alpha:[NHPref(@"statusOpacity",@0) floatValue]/255];
    [self rebuildKeyboard]; [self updateDirectionOverlay]; [self.view setNeedsLayout];
}
- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews]; BOOL landscape=self.view.bounds.size.width>self.view.bounds.size.height;
    if(self.lastLandscape!=landscape) { self.lastLandscape=landscape; [self applyPreferences]; }
    CGRect area=UIEdgeInsetsInsetRect(self.view.bounds,self.view.safeAreaInsets);
    if(!self.keyboardPanel.hidden) { CGFloat h=MIN(216,area.size.height*0.48); self.keyboardPanel.frame=CGRectMake(area.origin.x,CGRectGetMaxY(area)-h,area.size.width,h); area.size.height-=h; [self layoutKeyboard]; }
    for(NSUInteger i=0;i<self.panels.count;i++) {
        UIView *p=self.panels[i]; NSDictionary *d=self.panelDefinitions[i]; int loc=[d[@"loc"] intValue]; CGFloat s=[d[@"size"] floatValue];
        if(loc==0) { p.frame=CGRectMake(area.origin.x,area.origin.y,s,area.size.height); area.origin.x+=s; area.size.width-=s; }
        else if(loc==1) { p.frame=CGRectMake(CGRectGetMaxX(area)-s,area.origin.y,s,area.size.height); area.size.width-=s; }
        else if(loc==2) { p.frame=CGRectMake(area.origin.x,area.origin.y,area.size.width,s); area.origin.y+=s; area.size.height-=s; }
        else { p.frame=CGRectMake(area.origin.x,CGRectGetMaxY(area)-s,area.size.width,s); area.size.height-=s; }
    }
    CGFloat width=MAX(1,area.size.width); self.status.frame=CGRectMake(area.origin.x,area.origin.y,width,34);
    CGFloat mh=self.messages.text.length?MIN(90,MAX(22,[self.messages sizeThatFits:CGSizeMake(width,CGFLOAT_MAX)].height)):0;
    self.messages.frame=CGRectMake(area.origin.x,area.origin.y+34,width,mh);
    // The map occupies the available play area; messages/status overlay it as in ForkFront.
    self.scroll.frame=area;
    for(NSMutableDictionary *w in self.windows.allValues)if([w[@"type"] intValue]==2)[self updateStatus:w];
    int loc=[NHPref(landscape?@"ovlLandLoc":@"ovlPortLoc",@1) intValue]; CGSize ds=self.dpad.bounds.size;
    CGFloat dx=loc%3==0?area.origin.x:loc%3==1?CGRectGetMidX(area)-ds.width/2:CGRectGetMaxX(area)-ds.width;
    CGFloat dy=loc<3?CGRectGetMidY(area)-ds.height/2:CGRectGetMaxY(area)-ds.height;
    self.dpad.frame=CGRectMake(dx,dy,ds.width,ds.height);
    self.moreButton.frame=CGRectMake(CGRectGetMidX(area)-85,CGRectGetMaxY(area)-40,170,36);
    [self.view bringSubviewToFront:self.status]; [self.view bringSubviewToFront:self.messages]; [self.view bringSubviewToFront:self.dpad]; [self.view bringSubviewToFront:self.moreButton];
}
- (void)updateDirectionOverlay {
    BOOL landscape=self.view.bounds.size.width>self.view.bounds.size.height;
    self.dpad.hidden=!(self.expectsDirection||[NHPref(landscape?@"ovlLand":@"ovlPort",@NO) boolValue]);
}
- (void)rebuildKeyboard {
    for(UIView *v in self.keyboardPanel.subviews)[v removeFromSuperview];
    NSArray *rows=self.keyboardLayouts[self.keyboardMode] ?: self.keyboardLayouts[@"qwerty"];
    for(NSUInteger r=0;r<rows.count;r++) {
        NSArray *row=rows[r];
        for(NSDictionary *key in row) {
            int code=[key[@"code"] intValue]; NSString *label=key[@"label"];
            if(!label.length && code!=0)label=code==-1?@"Shift":code==-5?@"⌫":code==10?@"Enter":code==32?@"Space":@"?";
            if(self.shift && code>='a'&&code<='z')label=label.uppercaseString;
            NHCommandButton *b=[self button:label command:[NSString stringWithFormat:@"key:%d",code]]; b.tag=r; b.accessibilityValue=[key[@"width"] description];
            if((code==-1&&self.shift)||(code==-7&&[self.keyboardMode isEqual:@"ctrl"])||(code==-10&&[self.keyboardMode isEqual:@"meta"]))b.backgroundColor=UIColor.darkGrayColor;
            [self.keyboardPanel addSubview:b];
        }
    }
    // Android Back has no iPhone equivalent. Expose Esc/Space/Hide in an extra strip.
    for(NSArray *pair in @[@[@"Esc",@"escape"],@[@"Space",@"space"],@[@"Hide",@"..."]]) { NHCommandButton *b=[self button:pair[0] command:pair[1]]; b.tag=rows.count; b.accessibilityValue=@"33.333"; [self.keyboardPanel addSubview:b]; }
    [self.view setNeedsLayout];
}
- (void)layoutKeyboard {
    NSInteger count=[self.keyboardLayouts[self.keyboardMode] count]+1; CGFloat h=self.keyboardPanel.bounds.size.height/MAX(1,count),w=self.keyboardPanel.bounds.size.width;
    for(NSInteger r=0;r<count;r++) {
        NSArray *buttons=[self.keyboardPanel.subviews filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(UIView *b,NSDictionary *bindings){return b.tag==r;}]];
        CGFloat total=0; for(UIView *b in buttons)total+=[b.accessibilityValue floatValue];
        CGFloat x=0; for(UIView *b in buttons) { CGFloat width=w*[b.accessibilityValue floatValue]/MAX(1,total); b.frame=CGRectMake(x+1,r*h+1,width-2,h-2); x+=width; }
    }
}
- (void)command:(NHCommandButton *)b {
    NSString *cmd=b.command;
    if([cmd isEqual:@"menu"]) { [self showMenu]; return; }
    if([cmd isEqual:@"..."]) { self.keyboardPanel.hidden=!self.keyboardPanel.hidden; [self.view setNeedsLayout]; return; }
    if([cmd isEqual:@"escape"]) { [self enqueue:@[@27]]; return; }
    if([cmd isEqual:@"space"]||[cmd isEqual:@"continue"]) { [self enqueue:@[@32]]; return; }
    if([cmd hasPrefix:@"key:"]) {
        int c=[[cmd substringFromIndex:4] intValue];
        if(c==-1) { self.shift=!self.shift; [self rebuildKeyboard]; return; }
        if(c==-9||c==-7||c==-10) { NSString *mode=c==-9?@"symbols":c==-7?@"ctrl":@"meta"; self.keyboardMode=[self.keyboardMode isEqual:mode]?@"qwerty":mode; [self rebuildKeyboard]; return; }
        if(c==-2||c==-11) { self.keyboardMode=@"qwerty"; [self rebuildKeyboard]; return; }
        if(c==-3) { self.keyboardPanel.hidden=YES; [self.view setNeedsLayout]; return; }
        if(c==-5)c=127;
        if(c==-8)c=27;
        if(c<=0)return;
        if(self.shift&&c>='a'&&c<='z')c-=32;
        [self enqueue:@[@(c)]]; if(self.shift) {self.shift=NO; [self rebuildKeyboard];} return;
    }
    for(NSNumber *c in NHCommandKeys(cmd))[self enqueue:@[c]];
}
- (void)showMenu {
    if(self.presentedViewController)return;
    UIAlertController *menu=[UIAlertController alertControllerWithTitle:@"NetHack" message:nil preferredStyle:UIAlertControllerStyleActionSheet];
    [menu addAction:[UIAlertAction actionWithTitle:@"Settings" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a){ [self afterDismiss:menu perform:^{[self showSettings];}]; }]];
    [menu addAction:[UIAlertAction actionWithTitle:@"Message history" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a){ [self afterDismiss:menu perform:^{[self showHistory];}]; }]];
    [menu addAction:[UIAlertAction actionWithTitle:@"Save and exit" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a){[self enqueue:@[@128]];}]];
    [menu addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    menu.popoverPresentationController.sourceView=self.status; menu.popoverPresentationController.sourceRect=self.status.bounds; [self presentViewController:menu animated:YES completion:nil];
}
- (void)afterDismiss:(UIViewController *)controller perform:(void (^)(void))action {
    [controller dismissViewControllerAnimated:YES completion:action];
}
- (NSArray *)settingsRows {
    NSArray *locations=@[@"Left",@"Right",@"Top",@"Bottom"]; NSMutableArray *panels=[NSMutableArray new];
    for(int i=0;i<6;i++) { NSString *p=[NSString stringWithFormat:@"p%d.",i];
        [panels addObject:@{@"title":[NSString stringWithFormat:@"Panel %d",i+1],@"rows":@[
            NHBool(@"Active in portrait",[p stringByAppendingString:@"port"],i==0),NHBool(@"Active in landscape",[p stringByAppendingString:@"land"],i==0),
            @{@"title":@"Command buttons",@"key":[p stringByAppendingString:@"commands"],@"default":i==0?NHDefaultPanel:@"",@"help":@"Space-separated commands; command|label, ^d, M-x, 20s. Escape spaces with a backslash."},
            NHChoice(@"Portrait location",[p stringByAppendingString:@"portLoc"],locations,3), NHChoice(@"Landscape location",[p stringByAppendingString:@"landLoc"],locations,3),
            NHNumber(@"Size (-10 to 10)",[p stringByAppendingString:@"size"],0,-10,10), NHNumber(@"Opacity (32 to 255)",[p stringByAppendingString:@"opacity"],255,32,255)
        ]}];
    }
    NSArray *dloc=@[@"Left",@"Center",@"Right",@"Bottom left",@"Bottom center",@"Bottom right"];
    return @[
        NHChoice(@"Tileset",@"tiles",@[@"Ascii (no tiles)",@"Default",@"Geoduck",@"Nevanda"],1),
        NHChoice(@"Travel command",@"travel",@[@"Never",@"After map is panned",@"Always"],1),
        NHBool(@"Lock view when the map fits",@"lockView",YES),NHBool(@"Monospace mode",@"monospace",NO),NHNumber(@"Status background opacity",@"statusOpacity",0,0,255),
        @{@"title":@"Directional overlay",@"rows":@[
            NHBool(@"Always show in portrait",@"ovlPort",NO), NHBool(@"Always show in landscape",@"ovlLand",NO),
            NHChoice(@"Portrait location",@"ovlPortLoc",dloc,1),NHChoice(@"Landscape location",@"ovlLandLoc",dloc,1),
            NHNumber(@"Size (-10 to 10)",@"ovlSize",0,-10,10),NHNumber(@"Opacity (32 to 255)",@"ovlOpacity",255,32,255), NHBool(@"Allow map input with overlay",@"allowMapDir",NO)]},
        @{@"title":@"Command panels",@"rows":panels}
    ];
}
- (void)showSettings {
    NHPreferences *p=[[NHPreferences alloc] initWithStyle:UITableViewStyleInsetGrouped]; p.title=@"NetHack Settings"; p.rows=[self settingsRows];
    __weak NHGame *weak=self; p.changed=^{ [weak applyPreferences]; };
    UINavigationController *nav=[[UINavigationController alloc] initWithRootViewController:p]; nav.overrideUserInterfaceStyle=UIUserInterfaceStyleDark; [self presentViewController:nav animated:YES completion:nil];
}
- (void)panelHold:(UILongPressGestureRecognizer *)hold { if(hold.state==UIGestureRecognizerStateBegan)[self showSettings]; }
- (void)historyHold:(UILongPressGestureRecognizer *)hold { if(hold.state==UIGestureRecognizerStateBegan)[self showHistory]; }
- (void)messageTap { if(self.waitingKey)[self enqueue:@[@32]]; else [self showHistory]; }
- (void)showHistory {
    if(self.presentedViewController)return;
    NHMenu *m=[NHMenu new]; m.title=@"Message history"; NSMutableArray *items=[NSMutableArray new];
    for(NSString *s in self.history)[items addObject:@{@"id":@0,@"text":s}]; m.items=items; m.how=0;
    UINavigationController *nav=[[UINavigationController alloc] initWithRootViewController:m]; nav.overrideUserInterfaceStyle=UIUserInterfaceStyleDark; [self presentViewController:nav animated:YES completion:nil];
}
- (void)updateStatus:(NSMutableDictionary *)window {
    NSArray *lines=window[@"statusLines"]; if(!lines)return;
    NSMutableAttributedString *text=[NSMutableAttributedString new];
    for(NSUInteger i=0;i<lines.count;i++) { if(i)[text appendAttributedString:[[NSAttributedString alloc] initWithString:@"\n"]]; [text appendAttributedString:lines[i]]; }
    CGFloat width=MAX(100,self.status.bounds.size.width),longest=1;
    for(NSAttributedString *line in lines)longest=MAX(longest,[line.string sizeWithAttributes:@{NSFontAttributeName:[UIFont monospacedSystemFontOfSize:15 weight:UIFontWeightRegular]}].width);
    [text addAttribute:NSFontAttributeName value:[UIFont monospacedSystemFontOfSize:MIN(15,15*width/longest) weight:UIFontWeightRegular] range:NSMakeRange(0,text.length)]; self.status.attributedText=text;
}

- (void)writeUIReady:(NSString *)name {
    NSURL *docs=[NSFileManager.defaultManager URLsForDirectory:NSDocumentDirectory inDomains:NSUserDomainMask].firstObject;
    [@"PASS" writeToURL:[docs URLByAppendingPathComponent:name] atomically:YES encoding:NSUTF8StringEncoding error:NULL];
}
