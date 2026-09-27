#import <UIKit/UIKit.h>
#import "Bridge.h"
#import "GurrUI.h"
#include <math.h>

static UIColor *NHColor(int rgb) {
    return [UIColor colorWithRed:((rgb>>16)&255)/255.0 green:((rgb>>8)&255)/255.0 blue:(rgb&255)/255.0 alpha:1];
}
@interface NHMap : UIView
@property NSMutableDictionary<NSNumber *,NSArray *> *cells;
@property UIImage *tiles;
@property CGSize tileSize;
@property CGPoint cursor;
@property CGPoint origin;
@property CGFloat scale;
- (CGPoint)tileAtViewPoint:(CGPoint)point;
- (CGPoint)centerForTile:(CGPoint)tile;
- (void)centerOnTile:(CGPoint)tile lockView:(BOOL)lockView;
- (BOOL)panBy:(CGPoint)delta allowWhenLocked:(BOOL)allowWhenLocked;
- (BOOL)zoomByFactor:(CGFloat)factor aroundPoint:(CGPoint)point;
@end
@implementation NHMap
- (instancetype)init {
    if ((self=[super initWithFrame:CGRectZero])) {
        self.cells=[NSMutableDictionary new]; self.backgroundColor=UIColor.blackColor;
        self.tiles=[UIImage imageWithContentsOfFile:[NSBundle.mainBundle pathForResource:@"default_16x16" ofType:@"png"]];
        self.cursor=CGPointMake(-1,-1); self.tileSize=CGSizeMake(16,16); self.scale=1;
    } return self;
}
- (CGPoint)tileAtViewPoint:(CGPoint)point {
    CGFloat side=24*MAX(0.01,self.scale);
    return CGPointMake(floor((point.x-self.origin.x)/side),floor((point.y-self.origin.y)/side));
}
- (CGPoint)centerForTile:(CGPoint)tile {
    CGFloat side=24*self.scale;
    return CGPointMake(self.origin.x+(tile.x+0.5)*side,self.origin.y+(tile.y+0.5)*side);
}
- (void)centerOnTile:(CGPoint)tile lockView:(BOOL)lockView {
    CGFloat side=24*self.scale, mapWidth=80*side, mapHeight=21*side;
    if(lockView && mapWidth<=self.bounds.size.width && mapHeight<=self.bounds.size.height) {
        self.origin=CGPointMake((self.bounds.size.width-mapWidth)/2,(self.bounds.size.height-mapHeight)/2);
    } else {
        self.origin=CGPointMake(self.bounds.size.width/2-(tile.x+0.5)*side,self.bounds.size.height/2-(tile.y+0.5)*side);
    }
    [self setNeedsDisplay];
}
- (BOOL)panBy:(CGPoint)delta allowWhenLocked:(BOOL)allowWhenLocked {
    CGFloat side=24*self.scale;
    BOOL locked=[NHPref(@"lockView",@YES) boolValue] && 80*side<=self.bounds.size.width && 21*side<=self.bounds.size.height;
    if(locked && !allowWhenLocked)return NO;
    self.origin=CGPointMake(self.origin.x+delta.x,self.origin.y+delta.y);
    [self setNeedsDisplay]; return YES;
}
- (BOOL)zoomByFactor:(CGFloat)factor aroundPoint:(CGPoint)point {
    if(!isfinite(factor) || factor<=0)return NO;
    CGFloat oldScale=self.scale, next=MIN(4,MAX(0.2,oldScale*factor));
    if(fabs(next-oldScale)<0.0001)return NO;
    CGFloat side=24*oldScale;
    CGPoint tile=CGPointMake((point.x-self.origin.x)/side,(point.y-self.origin.y)/side);
    self.scale=next;
    CGFloat nextSide=24*next;
    self.origin=CGPointMake(point.x-tile.x*nextSide,point.y-tile.y*nextSide);
    [self setNeedsDisplay]; return YES;
}
- (void)drawRect:(CGRect)rect {
    CGContextRef ctx=UIGraphicsGetCurrentContext(); CGContextSetInterpolationQuality(ctx,kCGInterpolationNone);
    CGFloat side=24*self.scale;
    for (NSNumber *key in self.cells) {
        int k=key.intValue; CGRect r=CGRectMake(self.origin.x+(k%80)*side,self.origin.y+(k/80)*side,side,side);
        if (!CGRectIntersectsRect(rect,r)) continue;
        NSArray *v=self.cells[key]; int tile=[v[0] intValue];
        int tw=MAX(1,self.tileSize.width),th=MAX(1,self.tileSize.height); int cols=(int)self.tiles.size.width/tw, rows=(int)self.tiles.size.height/th;
        if (cols>0 && tile>=0 && tile<cols*rows) {
            CGImageRef crop=CGImageCreateWithImageInRect(self.tiles.CGImage,CGRectMake((tile%cols)*tw,(tile/cols)*th,tw,th));
            [[UIImage imageWithCGImage:crop] drawInRect:r]; CGImageRelease(crop);
        } else {
            unichar c=[v[1] intValue]; [[NSString stringWithCharacters:&c length:1] drawInRect:CGRectInset(r,0.5,0.5) withAttributes:@{
                NSFontAttributeName:[UIFont monospacedSystemFontOfSize:21*self.scale weight:UIFontWeightRegular],NSForegroundColorAttributeName:NHColor([v[2] intValue])}];
        }
    }
    if(self.cursor.x>=0) {
        [UIColor.yellowColor setStroke]; CGContextSetLineWidth(ctx,MAX(1,self.scale));
        CGContextStrokeRect(ctx,CGRectMake(self.origin.x+self.cursor.x*side+1,self.origin.y+self.cursor.y*side+1,side-2,side-2));
    }
}
@end

@class NHGame;
@interface NHMenu : NSObject
@property NSArray<NSDictionary *> *items;
@property NSMutableDictionary<NSNumber *,NSNumber *> *selection;
@property int how;
@property(copy) void (^finish)(id);
@property(nonatomic,copy) NSString *title;
@property(nonatomic,strong) NHGurrOverlay *overlay;
@property(nonatomic,strong) UIStackView *rows;
@property(nonatomic,strong) UIScrollView *list;
@property(nonatomic,strong) NSArray<NSNumber *> *accelerators;
@property(nonatomic,strong) UIImage *tileImage;
@property(nonatomic) CGSize tileSize;
@property(nonatomic) NSInteger focusedIndex;
@property(nonatomic) NSInteger keyboardCount;
@property(nonatomic) BOOL allSelected;
@property(nonatomic,strong) UIButton *selectAllButton;
- (void)presentInView:(UIView *)view;
- (void)activateRow:(NSUInteger)index;
@end
@implementation NHMenu
- (BOOL)isHeader:(NSDictionary *)item {
    return [item[@"id"] longLongValue]==0 && [item[@"acc"] intValue]==0 && [item[@"attr"] intValue]==2;
}
- (NSDictionary<NSString *,NSString *> *)displayPartsForItem:(NSDictionary *)item {
    NSString *text=item[@"text"] ?: @"";
    if([self isHeader:item])return @{@"name":text,@"subtext":@""};
    NSRange weightOpen=[text rangeOfString:@"{" options:NSBackwardsSearch];
    NSRange weightClose=[text rangeOfString:@"}" options:NSBackwardsSearch];
    NSRange status=[text rangeOfString:@" (" options:NSBackwardsSearch];
    NSRange statusClose=[text rangeOfString:@")" options:NSBackwardsSearch];
    BOOL hasStatus=status.location!=NSNotFound && statusClose.location>status.location &&
        (statusClose.location==text.length-1 || (weightClose.location==text.length-1 && weightOpen.location>statusClose.location));
    NSUInteger nameEnd=text.length;
    NSMutableArray<NSString *> *subtext=[NSMutableArray new];
    if(hasStatus) {
        nameEnd=status.location+1;
        [subtext addObject:[text substringWithRange:NSMakeRange(status.location+2,statusClose.location-status.location-2)]];
    }
    if(weightOpen.location!=NSNotFound && weightClose.location>weightOpen.location) {
        if(!hasStatus)nameEnd=MIN(nameEnd,weightOpen.location);
        [subtext addObject:[@"w:" stringByAppendingString:[text substringWithRange:NSMakeRange(weightOpen.location+1,weightClose.location-weightOpen.location-1)]]];
    }
    NSString *name=[[text substringToIndex:nameEnd] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    NSUInteger countEnd=0;
    while(countEnd<name.length && [NSCharacterSet.decimalDigitCharacterSet characterIsMember:[name characterAtIndex:countEnd]])countEnd++;
    if(countEnd && [[name substringToIndex:countEnd] longLongValue]>0)
        name=[[name substringFromIndex:countEnd] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    return @{@"name":name,@"subtext":[subtext componentsJoinedByString:@"; "]};
}
- (NSInteger)maxCountForItem:(NSDictionary *)item {
    NSString *text=item[@"text"] ?: @""; NSScanner *scanner=[NSScanner scannerWithString:text]; unsigned long long value=0;
    if([scanner scanUnsignedLongLong:&value] && value>0 && scanner.scanLocation>0)return (NSInteger)MIN(value,(unsigned long long)NSIntegerMax);
    return 1;
}
- (NSArray<NSNumber *> *)preparedAccelerators {
    BOOL explicit=NO; for(NSDictionary *item in self.items) if([item[@"acc"] intValue]) { explicit=YES; break; }
    NSMutableArray *result=[NSMutableArray new]; unichar next='a';
    for(NSDictionary *item in self.items) {
        NSInteger acc=[item[@"acc"] intValue];
        if(!explicit && ![self isHeader:item] && [item[@"id"] longLongValue]) {
            if(next=='z'+1)next='A'; else if(next=='Z'+1)next=0;
            if(next) { acc=next; next++; }
        }
        [result addObject:@(acc)];
    }
    return result;
}
- (void)presentInView:(UIView *)view {
    self.selection=[NSMutableDictionary new]; self.keyboardCount=-1; self.focusedIndex=-1;
    for(NSDictionary *item in self.items) if([item[@"selected"] boolValue] && [item[@"id"] longLongValue]) self.selection[item[@"id"]]=@(-1);
    self.accelerators=[self preparedAccelerators];
    if(!self.overlay)self.overlay=[[NHGurrOverlay alloc] initWithTitle:self.title ?: @"NetHack"];
    self.list=[UIScrollView new]; self.list.translatesAutoresizingMaskIntoConstraints=NO; self.list.accessibilityIdentifier=@"gurr.menu.list";
    self.rows=[UIStackView new]; self.rows.axis=UILayoutConstraintAxisVertical; self.rows.spacing=3; self.rows.translatesAutoresizingMaskIntoConstraints=NO;
    [self.list addSubview:self.rows];
    [NSLayoutConstraint activateConstraints:@[
        [self.rows.topAnchor constraintEqualToAnchor:self.list.contentLayoutGuide.topAnchor], [self.rows.bottomAnchor constraintEqualToAnchor:self.list.contentLayoutGuide.bottomAnchor],
        [self.rows.leadingAnchor constraintEqualToAnchor:self.list.contentLayoutGuide.leadingAnchor], [self.rows.trailingAnchor constraintEqualToAnchor:self.list.contentLayoutGuide.trailingAnchor],
        [self.rows.widthAnchor constraintEqualToAnchor:self.list.frameLayoutGuide.widthAnchor]
    ]];
    CGFloat safeHeight=MAX(0,view.bounds.size.height-view.safeAreaInsets.top-view.safeAreaInsets.bottom);
    [self.overlay addCustomView:self.list height:MIN(430,MAX(120,safeHeight-220))];
    for(NSUInteger i=0;i<self.items.count;i++) [self addRowAtIndex:i];
    __weak NHMenu *weakSelf=self;
    self.overlay.hardwareKeyHandler=^BOOL(unichar key){ return [weakSelf handleKey:key]; };
    if(self.how==2) {
        self.selectAllButton=[self.overlay addActionWithTitle:@"Select all" primary:NO handler:^{ [weakSelf selectAll:!weakSelf.allSelected]; }];
        [self.overlay addActionWithTitle:@"Done" primary:YES handler:^{ [weakSelf accept]; }];
        [self.overlay addActionWithTitle:@"Cancel" primary:NO handler:^{ [weakSelf complete:nil]; }];
    } else if(self.how==1) {
        [self.overlay addActionWithTitle:@"Cancel" primary:NO handler:^{ [weakSelf complete:nil]; }];
        [self.overlay addActionWithTitle:@"OK" primary:YES handler:^{ [weakSelf accept]; }];
    } else {
        [self.overlay addActionWithTitle:self.how==0?@"Close":@"Cancel" primary:NO handler:^{ if(weakSelf.how==0)[weakSelf accept]; else [weakSelf complete:nil]; }];
    }
    [self.overlay presentInView:view focusInput:NO];
}
- (NSString *)rowTitle:(NSUInteger)index {
    NSDictionary *item=self.items[index]; NSNumber *ident=item[@"id"];
    BOOL selectable=[ident longLongValue]!=0 && ![self isHeader:item];
    unichar acc=index<self.accelerators.count?[self.accelerators[index] unsignedShortValue]:0;
    NSString *shortcut=selectable&&acc?[NSString stringWithFormat:@"%C",acc]:@" ";
    NSNumber *count=self.selection[ident];
    NSString *check=self.how==2&&selectable?(count?@"[x] ":@"[ ] "):@"";
    if(selectable && count && count.longLongValue>0)check=[NSString stringWithFormat:@"%@%ld ",check,(long)count.longValue];
    NSDictionary *parts=[self displayPartsForItem:item];
    NSString *name=parts[@"name"] ?: @"", *subtext=parts[@"subtext"] ?: @"";
    return [NSString stringWithFormat:@"%@%@  %@%@%@",check,shortcut,name,subtext.length?@"\n":@"",subtext];
}
- (NSAttributedString *)styledTitleForRow:(NSUInteger)index font:(UIFont *)font {
    NSDictionary *item=self.items[index]; NSInteger attr=[item[@"attr"] intValue]; BOOL header=[self isHeader:item];
    UIColor *color=header?UIColor.blackColor:((attr&4)?UIColor.lightGrayColor:((attr&32)?[UIColor colorWithRed:1 green:0.7 blue:0.2 alpha:1]:UIColor.whiteColor));
    if(item[@"color"] && item[@"color"]!=NSNull.null && [item[@"color"] intValue])color=NHColor([item[@"color"] intValue]);
    if(attr&2)font=[UIFont monospacedSystemFontOfSize:font.pointSize weight:UIFontWeightSemibold];
    NSMutableDictionary *attributes=[@{NSFontAttributeName:font,NSForegroundColorAttributeName:color} mutableCopy];
    if(attr&16)attributes[NSUnderlineStyleAttributeName]=@(NSUnderlineStyleSingle);
    NSMutableAttributedString *title=[[NSMutableAttributedString alloc] initWithString:[self rowTitle:index] attributes:attributes];
    NSRange subtext=[title.string rangeOfString:@"\n" options:NSBackwardsSearch];
    if(subtext.location!=NSNotFound && subtext.location+1<title.length)
        [title addAttribute:NSForegroundColorAttributeName value:UIColor.lightGrayColor range:NSMakeRange(subtext.location+1,title.length-subtext.location-1)];
    return title;
}
- (void)addRowAtIndex:(NSUInteger)index {
    NSDictionary *item=self.items[index]; BOOL header=[self isHeader:item]; NSInteger attr=[item[@"attr"] intValue];
    UIButton *button=[UIButton buttonWithType:UIButtonTypeCustom]; button.tag=10000+index;
    button.accessibilityIdentifier=[NSString stringWithFormat:@"gurr.menu.row.%lu",(unsigned long)index];
    button.contentHorizontalAlignment=UIControlContentHorizontalAlignmentLeft; button.contentEdgeInsets=UIEdgeInsetsMake(7,10,7,8);
    button.titleLabel.numberOfLines=0; button.titleLabel.font=[UIFont monospacedSystemFontOfSize:15 weight:(header||(attr&2))?UIFontWeightBold:UIFontWeightRegular];
    button.layer.cornerRadius=3; button.backgroundColor=header?[UIColor colorWithWhite:0.82 alpha:1]:[UIColor colorWithWhite:0.20 alpha:1];
    [button setAttributedTitle:[self styledTitleForRow:index font:button.titleLabel.font] forState:UIControlStateNormal];
    if(self.tileImage.CGImage && self.tileSize.width>0 && self.tileSize.height>0) {
        NSInteger tile=[item[@"tile"] integerValue]; NSInteger tw=self.tileSize.width,th=self.tileSize.height,cols=(NSInteger)self.tileImage.size.width/tw;
        if(tile>=0 && cols>0) { CGImageRef crop=CGImageCreateWithImageInRect(self.tileImage.CGImage,CGRectMake((tile%cols)*tw,(tile/cols)*th,tw,th)); if(crop) { [button setImage:[UIImage imageWithCGImage:crop] forState:UIControlStateNormal]; CGImageRelease(crop); button.imageView.contentMode=UIViewContentModeScaleAspectFit; button.imageEdgeInsets=UIEdgeInsetsMake(2,0,2,6); button.titleEdgeInsets=UIEdgeInsetsMake(0,6,0,0); } }
    }
    __weak NHMenu *weakSelf=self;
    [button addAction:[UIAction actionWithHandler:^(__kindof UIAction *action){ [weakSelf activateRow:index]; }] forControlEvents:UIControlEventTouchUpInside];
    UILongPressGestureRecognizer *hold=[[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(rowHeld:)]; hold.minimumPressDuration=0.55; [button addGestureRecognizer:hold];
    [self.rows addArrangedSubview:button];
}
- (void)refreshRows {
    for(NSUInteger i=0;i<self.items.count;i++) if(i<self.rows.arrangedSubviews.count) {
        UIButton *button=(UIButton *)self.rows.arrangedSubviews[i]; NSDictionary *item=self.items[i]; NSNumber *ident=item[@"id"]; BOOL selected=self.selection[ident]!=nil;
        UIColor *color=[self isHeader:item]?[UIColor colorWithWhite:0.82 alpha:1]:(selected?[UIColor colorWithRed:0.18 green:0.32 blue:0.22 alpha:1]:[UIColor colorWithWhite:0.20 alpha:1]);
        button.backgroundColor=color;
        [button setAttributedTitle:[self styledTitleForRow:i font:button.titleLabel.font] forState:UIControlStateNormal];
    }
    if(self.selectAllButton)[self.selectAllButton setTitle:self.allSelected?@"Clear all":@"Select all" forState:UIControlStateNormal];
}
- (void)activateRow:(NSUInteger)index {
    if(index>=self.items.count)return;
    self.focusedIndex=index; NSDictionary *item=self.items[index]; NSNumber *ident=item[@"id"];
    if(self.how==0) { [self accept]; return; }
    if(![ident longLongValue]) { if(self.how==2 && [self isHeader:item])[self toggleGroupAt:index]; return; }
    if(self.how==1) {
        [self.selection removeAllObjects];
        self.selection[ident]=@(self.keyboardCount>=0?MIN(self.keyboardCount,[self maxCountForItem:item]):-1);
        [self accept]; return;
    }
    NSNumber *current=self.selection[ident];
    if(self.keyboardCount==0)[self.selection removeObjectForKey:ident];
    else if(self.keyboardCount>0)self.selection[ident]=@(MIN(self.keyboardCount,[self maxCountForItem:item]));
    else if(current)[self.selection removeObjectForKey:ident]; else self.selection[ident]=@(-1);
    self.keyboardCount=-1; self.allSelected=NO; [self refreshRows];
}
- (void)toggleGroupAt:(NSUInteger)index {
    BOOL shouldSelect=NO;
    for(NSUInteger i=index+1;i<self.items.count && ![self isHeader:self.items[i]];i++) {
        NSDictionary *item=self.items[i]; if([item[@"id"] longLongValue] && !self.selection[item[@"id"]]){shouldSelect=YES;break;}
    }
    for(NSUInteger i=index+1;i<self.items.count && ![self isHeader:self.items[i]];i++) {
        NSDictionary *item=self.items[i]; NSNumber *ident=item[@"id"];
        if([ident longLongValue]) { if(shouldSelect)self.selection[ident]=@(-1); else [self.selection removeObjectForKey:ident]; }
    }
    self.keyboardCount=-1; self.allSelected=NO; [self refreshRows];
}
- (void)selectAll:(BOOL)select {
    if(select) { for(NSDictionary *item in self.items) if([item[@"id"] longLongValue])self.selection[item[@"id"]]=@(-1); }
    else [self.selection removeAllObjects];
    self.allSelected=select; self.keyboardCount=-1; [self refreshRows];
}
- (NHBuffer *)resultBuffer {
    NHBuffer *buffer=[NHBuffer count:self.selection.count*2 size:sizeof(jlong)]; jlong *out=buffer.data.mutableBytes;
    for(NSDictionary *item in self.items) { NSNumber *value=self.selection[item[@"id"]]; if(value) { *out++=[item[@"id"] longLongValue]; *out++=value.longLongValue; } }
    return buffer;
}
- (void)accept {
    if(self.how==0) { [self complete:[NHBuffer count:0 size:sizeof(jlong)]]; return; }
    if(self.how==1) {
        if(self.focusedIndex<0 || self.focusedIndex>=self.items.count) { [self complete:nil]; return; }
        NSDictionary *item=self.items[self.focusedIndex]; if(![item[@"id"] longLongValue]) { [self complete:nil]; return; }
        if(!self.selection[item[@"id"]])self.selection[item[@"id"]]=@(-1);
    }
    [self complete:[self resultBuffer]];
}
- (void)complete:(id)value {
    NHGurrOverlay *overlay=self.overlay; self.overlay=nil;
    void (^callback)(id)=self.finish; self.finish=nil;
    [overlay dismiss]; if(callback)callback(value);
}
- (void)showQuantityForIndex:(NSUInteger)index {
    if(self.how==0 || index>=self.items.count)return;
    NSDictionary *item=self.items[index]; NSInteger maximum=[self maxCountForItem:item]; if(maximum<2)return;
    self.focusedIndex=index;
    NHGurrOverlay *dialog=[[NHGurrOverlay alloc] initWithTitle:@"Quantity"];
    [dialog addMessage:item[@"text"] ?: @""];
    UILabel *valueLabel=[UILabel new]; valueLabel.textAlignment=NSTextAlignmentCenter; valueLabel.textColor=UIColor.whiteColor; valueLabel.font=[UIFont monospacedSystemFontOfSize:22 weight:UIFontWeightSemibold]; valueLabel.text=[NSString stringWithFormat:@"%ld",(long)maximum];
    UISlider *slider=[UISlider new]; slider.minimumValue=1; slider.maximumValue=maximum; slider.value=maximum;
    [slider addAction:[UIAction actionWithHandler:^(__kindof UIAction *action){ NSInteger n=MAX(1,lroundf(slider.value)); slider.value=n; valueLabel.text=[NSString stringWithFormat:@"%ld",(long)n]; }] forControlEvents:UIControlEventValueChanged];
    UIStackView *controls=[[UIStackView alloc] initWithArrangedSubviews:@[valueLabel,slider]]; controls.axis=UILayoutConstraintAxisVertical; controls.spacing=10;
    [dialog addCustomView:controls height:86]; __weak NHGurrOverlay *weakDialog=dialog; __weak NHMenu *weakSelf=self;
    [dialog addActionWithTitle:@"Cancel" primary:NO handler:^{ [weakDialog dismiss]; }];
    [dialog addActionWithTitle:@"Select" primary:YES handler:^{
        NSInteger count=MAX(1,lroundf(slider.value));
        if(weakSelf.how==1) { [weakSelf.selection removeAllObjects]; weakSelf.selection[item[@"id"]]=@(count); [weakSelf accept]; [weakDialog dismiss]; }
        else { weakSelf.selection[item[@"id"]]=@(count>=maximum?-1:count); [weakSelf refreshRows]; [weakDialog dismiss]; }
    }];
    dialog.hardwareKeyHandler=^BOOL(unichar key){ if(key==27){[weakDialog dismiss];return YES;} return NO; };
    [dialog presentInView:self.overlay focusInput:NO];
}
- (void)rowHeld:(UILongPressGestureRecognizer *)press {
    if(press.state!=UIGestureRecognizerStateBegan)return;
    NSUInteger index=press.view.tag-10000; if(index<self.items.count)[self showQuantityForIndex:index];
}
- (BOOL)handleKey:(unichar)key {
    if(key==27) { [self complete:nil]; return YES; }
    if(key==13||key==10||key==' ') {
        if(self.how==2 && self.focusedIndex>=0 && self.focusedIndex<self.items.count)[self activateRow:self.focusedIndex]; else [self accept];
        return YES;
    }
    if(key>='0'&&key<='9'&&self.how) { self.keyboardCount=MAX(0,self.keyboardCount)*10+key-'0'; return YES; }
    for(NSUInteger i=0;i<self.accelerators.count;i++) if([self.accelerators[i] unsignedShortValue]==key && [self.items[i][@"id"] longLongValue]) {
        [self activateRow:i]; return YES;
    }
    BOOL changed=NO;
    for(NSDictionary *item in self.items) if(self.how==2 && [item[@"group"] intValue]==key && [item[@"id"] longLongValue]) {
        NSNumber *ident=item[@"id"]; if(self.selection[ident])[self.selection removeObjectForKey:ident]; else self.selection[ident]=@(-1); changed=YES;
    }
    if(changed) { self.allSelected=NO; [self refreshRows]; return YES; }
    if(self.how==2 && key=='.') { [self selectAll:YES]; return YES; }
    if(self.how==2 && key=='-') { [self selectAll:NO]; return YES; }
    return NO;
}
@end
@interface NHGame : UIViewController <UITextFieldDelegate,UIGestureRecognizerDelegate>
@property NHMap *map;
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
@property NSMutableArray<UIScrollView *> *panels;
@property NSMutableArray<NSDictionary *> *panelDefinitions;
@property NSMutableArray<NSString *> *history;
@property UIView *keyboardPanel, *dpad;
@property NHCommandButton *moreButton;
@property NSDictionary *keyboardLayouts;
@property NSString *keyboardMode;
@property BOOL shift, lastLandscape, waitingKey;
@property NSInteger uiSmokeTurns;
@property CGFloat lastPinchScale;
@property BOOL modalControlsHidden, modalKeyboardPanelWasHidden, modalDpadWasHidden, modalMoreButtonWasHidden;
@property NSMutableArray<NSNumber *> *modalPanelHiddenStates;

- (void)enqueue:(NSArray *)event;
- (id)invoke:(NSString *)name arguments:(NSArray *)args;
- (NHGurrOverlay *)beginGameOverlay:(NSString *)title;
- (void)restoreGameControls;
- (NHGurrOverlay *)showLinePrompt:(NSString *)title initial:(NSString *)initial history:(NSArray<NSString *> *)history maxLength:(NSUInteger)maxLength focusInput:(BOOL)focusInput completion:(void (^)(NSString *,BOOL))completion;
- (NHGurrOverlay *)showQuestion:(NSString *)question choices:(NSString *)choices defaultKey:(int)defaultKey completion:(void (^)(int))completion;
- (void)runModalUISmokeSequence;
@end
static NHGame *game;
@implementation NHGame
#include "GurrFrontend.inc"
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
    if([NSProcessInfo.processInfo.arguments containsObject:@"--ui-smoke"]) {
        [@"OPTIONS=name:UIProbe,role:Valkyrie,race:human,gender:female,align:lawful\nOPTIONS=!legacy,!tutorial,!autopickup,force_invmenu\n" writeToURL:[dir URLByAppendingPathComponent:@"defaults.nh"] atomically:YES encoding:NSUTF8StringEncoding error:&error];
    }
    if(error) { self.messages.text=error.localizedDescription; return; }
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED,0),^{
        NHRun(dir.path.UTF8String);
        dispatch_async(dispatch_get_main_queue(),^{ self.ended=YES; self.status.text=@"게임이 종료되었습니다. 다시 실행하려면 앱을 닫고 열어주세요."; if(self.backgroundTask!=UIBackgroundTaskInvalid) { [UIApplication.sharedApplication endBackgroundTask:self.backgroundTask]; self.backgroundTask=UIBackgroundTaskInvalid; } });
    });
}
- (void)enqueue:(NSArray *)event { [self.inputCondition lock]; if(!self.ended && self.input.count<512) [self.input addObject:event]; [self.inputCondition signal]; [self.inputCondition unlock]; }
- (BOOL)textField:(UITextField *)f shouldChangeCharactersInRange:(NSRange)r replacementString:(NSString *)s { for(NSUInteger i=0;i<s.length;i++) [self enqueue:@[@([s characterAtIndex:i])]]; return NO; }
- (BOOL)textFieldShouldReturn:(UITextField *)f { [self enqueue:@[@13]]; [f resignFirstResponder]; return NO; }
- (void)mapTap:(UITapGestureRecognizer *)tap { [self touch:[tap locationInView:self.map] longPress:NO]; }
- (void)mapHold:(UILongPressGestureRecognizer *)hold { if(hold.state==UIGestureRecognizerStateBegan)[self touch:[hold locationInView:self.map] longPress:YES]; }
- (void)mapPan:(UIPanGestureRecognizer *)pan {
    if(pan.state==UIGestureRecognizerStateChanged || pan.state==UIGestureRecognizerStateBegan) {
        CGPoint delta=[pan translationInView:self.map];
        BOOL afterPan=[NHPref(@"travel",@1) intValue]==1;
        if([self.map panBy:delta allowWhenLocked:afterPan])self.panned=YES;
        [pan setTranslation:CGPointZero inView:self.map];
    }
}
- (void)mapPinch:(UIPinchGestureRecognizer *)pinch {
    if(pinch.state==UIGestureRecognizerStateBegan) { self.lastPinchScale=1; self.panned=NO; }
    else if(pinch.state==UIGestureRecognizerStateChanged) {
        CGFloat factor=pinch.scale/MAX(0.001,self.lastPinchScale); self.lastPinchScale=pinch.scale;
        if([self.map zoomByFactor:factor aroundPoint:[pinch locationInView:self.map]])NHSetPref(@"mapScale",@(self.map.scale));
    }
}
- (void)touch:(CGPoint)p longPress:(BOOL)hold {
    CGPoint tile=[self.map tileAtViewPoint:p]; int x=(int)tile.x,y=(int)tile.y; if(x<0||x>=80||y<0||y>=21)return;
    CGPoint playerCenter=[self.map centerForTile:self.player]; CGFloat dx=p.x-playerCenter.x,dy=p.y-playerCenter.y;
    BOOL onSelf=(x==(int)self.player.x && y==(int)self.player.y) || dx*dx+dy*dy<25*25;
    int travelMode=[NHPref(@"travel",@1) intValue];
    BOOL travel=travelMode==2 || (travelMode==1 && self.panned && (abs(x-(int)self.player.x)>3 || abs(y-(int)self.player.y)>3));
    if(self.waitingKey && !self.expectsDirection && !self.mouseLocked) { [self enqueue:@[@32]]; return; }
    if(self.mouseLocked || (!self.expectsDirection && (onSelf||travel))) {
        if(onSelf && !self.mouseLocked) { x=self.player.x; y=self.player.y; }
        [self enqueue:@[@0,@(x),@(y)]];
    } else {
        if(!self.dpad.hidden && ![NHPref(@"allowMapDir",@NO) boolValue])return;
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
- (NHGurrOverlay *)beginGameOverlay:(NSString *)title {
    [self.keyboard resignFirstResponder];
    if (!self.modalControlsHidden) {
        self.modalControlsHidden=YES; self.modalKeyboardPanelWasHidden=self.keyboardPanel.hidden;
        self.modalDpadWasHidden=self.dpad.hidden; self.modalMoreButtonWasHidden=self.moreButton.hidden;
        self.modalPanelHiddenStates=[NSMutableArray new];
        for (UIView *panel in self.panels) [self.modalPanelHiddenStates addObject:@(panel.hidden)];
        self.keyboardPanel.hidden=YES; self.dpad.hidden=YES; self.moreButton.hidden=YES;
        for (UIView *panel in self.panels) panel.hidden=YES;
    }
    NHGurrOverlay *overlay=[[NHGurrOverlay alloc] initWithTitle:title ?: @"NetHack"];
    __weak NHGame *weakSelf=self;
    overlay.onDismiss=^{ [weakSelf restoreGameControls]; };
    return overlay;
}
- (void)restoreGameControls {
    if (!self.modalControlsHidden) return;
    self.modalControlsHidden=NO; self.keyboardPanel.hidden=self.modalKeyboardPanelWasHidden;
    self.dpad.hidden=self.modalDpadWasHidden; self.moreButton.hidden=self.modalMoreButtonWasHidden;
    for (NSUInteger i=0;i<MIN(self.panels.count,self.modalPanelHiddenStates.count);i++) self.panels[i].hidden=[self.modalPanelHiddenStates[i] boolValue];
    self.modalPanelHiddenStates=nil; [self.view setNeedsLayout]; [self.view layoutIfNeeded];
}
- (NHGurrOverlay *)showLinePrompt:(NSString *)title initial:(NSString *)initial history:(NSArray<NSString *> *)history maxLength:(NSUInteger)maxLength focusInput:(BOOL)focusInput completion:(void (^)(NSString *,BOOL))completion {
    NHGurrOverlay *overlay=[[NHGurrOverlay alloc] initWithTitle:title ?: @"NetHack"];
    UITextField *field=[overlay addInputWithInitialText:initial keyboardType:UIKeyboardTypeASCIICapable maxLength:maxLength ?: 200];
    [overlay addHistoryItems:history select:nil];
    __weak NHGurrOverlay *weakOverlay=overlay; __weak UITextField *weakField=field;
    void (^finish)(BOOL)=^(BOOL cancelled){
        NSString *value=cancelled?@"\033":(weakField.text ?: @"");
        [weakOverlay dismiss]; if(completion)completion(value,cancelled);
    };
    overlay.onInputReturn=^{ finish(NO); }; overlay.onInputEscape=^{ finish(YES); };
    ((NHGurrInputField *)field).onEscape=^{ finish(YES); };
    [overlay addActionWithTitle:@"Cancel" primary:NO handler:^{ finish(YES); }];
    [overlay addActionWithTitle:@"OK" primary:YES handler:^{ finish(NO); }];
    __weak NHGame *weakSelf=self; overlay.onDismiss=^{ [weakSelf restoreGameControls]; };
    [self.keyboard resignFirstResponder];
    if (!self.modalControlsHidden) {
        self.modalControlsHidden=YES; self.modalKeyboardPanelWasHidden=self.keyboardPanel.hidden;
        self.modalDpadWasHidden=self.dpad.hidden; self.modalMoreButtonWasHidden=self.moreButton.hidden;
        self.modalPanelHiddenStates=[NSMutableArray new];
        for (UIView *panel in self.panels) [self.modalPanelHiddenStates addObject:@(panel.hidden)];
        self.keyboardPanel.hidden=YES; self.dpad.hidden=YES; self.moreButton.hidden=YES;
        for (UIView *panel in self.panels) panel.hidden=YES;
    }
    [overlay presentInView:self.view focusInput:focusInput]; return overlay;
}
- (NSArray<NSString *> *)promptHistoryForKey:(NSString *)key {
    NSArray *values=[NSUserDefaults.standardUserDefaults arrayForKey:key];
    NSMutableArray *items=[NSMutableArray new];
    for (id value in values) if ([value isKindOfClass:NSString.class] && [value length] && ![items containsObject:value]) [items addObject:value];
    return [items subarrayWithRange:NSMakeRange(0,MIN(items.count,10))];
}
- (void)rememberPromptValue:(NSString *)value forKey:(NSString *)key {
    if (!value.length || ![value stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet].length) return;
    NSMutableArray *items=[[self promptHistoryForKey:key] mutableCopy]; [items removeObject:value]; [items insertObject:value atIndex:0];
    if (items.count>10) [items removeObjectsInRange:NSMakeRange(10,items.count-10)];
    [NSUserDefaults.standardUserDefaults setObject:items forKey:key];
}
- (NSString *)initialTextForPrompt:(NSString *)title supplied:(NSString *)supplied history:(NSArray<NSString *> *)history {
    if ([title containsString:@"For what do you wish"]) return @"";
    NSArray *patterns=@[@"Replace annotation \x22",@"Replace previous annotation \x22",@" called ",@" named "];
    for (NSUInteger i=0;i<patterns.count;i++) {
        NSString *pattern=patterns[i];
        if (i<2 && [title hasPrefix:pattern]) {
            NSUInteger start=i==0?20:29; NSRange end=[title rangeOfString:@"\x22" options:NSBackwardsSearch];
            if (end.location!=NSNotFound && end.location>start) return [title substringWithRange:NSMakeRange(start,end.location-start)];
        } else if (i==2 && ([title hasPrefix:@"What do you want to call"] || [title hasPrefix:@"Call "])) {
            NSRange marker=[title rangeOfString:pattern]; if(marker.location!=NSNotFound && title.length>marker.location+pattern.length) return [title substringWithRange:NSMakeRange(marker.location+pattern.length,title.length-marker.location-pattern.length-1)];
        } else if (i==3 && [title hasPrefix:@"What do you want to name"]) {
            NSRange marker=[title rangeOfString:pattern]; if(marker.location!=NSNotFound && title.length>marker.location+pattern.length) return [title substringWithRange:NSMakeRange(marker.location+pattern.length,title.length-marker.location-pattern.length-1)];
        }
    }
    if (supplied.length) return supplied;
    return history.firstObject ?: @"";
}
- (NSString *)prompt:(NSString *)title initial:(NSString *)initial historyKey:(NSString *)historyKey maxLength:(NSUInteger)maxLength focusInput:(BOOL)focusInput {
    dispatch_semaphore_t ready=dispatch_semaphore_create(0); __block NSString *answer=nil;
    NSArray *history=[self promptHistoryForKey:historyKey];
    NSString *prefill=[self initialTextForPrompt:title supplied:initial history:history];
    dispatch_async(dispatch_get_main_queue(),^{
        [self showLinePrompt:title initial:prefill history:history maxLength:maxLength focusInput:focusInput completion:^(NSString *value,BOOL cancelled){
            answer=value;
            if(!cancelled) [self rememberPromptValue:value forKey:historyKey];
            dispatch_semaphore_signal(ready);
        }];
    });
    dispatch_semaphore_wait(ready,DISPATCH_TIME_FOREVER); return answer;
}
- (NHGurrOverlay *)showQuestion:(NSString *)question choices:(NSString *)choices defaultKey:(int)defaultKey completion:(void (^)(int))completion {
    NHGurrOverlay *overlay=[self beginGameOverlay:question ?: @"NetHack"];
    NSMutableArray<NSString *> *options=[NSMutableArray new];
    for (NSUInteger i=0;i<choices.length;i++) { unichar key=[choices characterAtIndex:i]; if(key) [options addObject:[NSString stringWithCharacters:&key length:1]]; }
    if (!options.count) { unichar fallback=(unichar)(defaultKey ?: 27); [options addObject:[NSString stringWithCharacters:&fallback length:1]]; }
    NSUInteger defaultIndex=0;
    for (NSUInteger i=0;i<options.count;i++) if([options[i] characterAtIndex:0]==(unichar)defaultKey) { defaultIndex=i; break; }
    NSString *lowerQuestion=question ?: @""; BOOL guarded=options.count==2 && [lowerQuestion hasPrefix:@"Really"];
    __block BOOL ready=!guarded; __weak NHGurrOverlay *weakOverlay=overlay;
    void (^selectIndex)(NSUInteger)=^(NSUInteger index){
        if(index>=options.count || (guarded && !ready && index!=defaultIndex)) return;
        int key=[options[index] characterAtIndex:0]; [weakOverlay dismiss]; if(completion)completion(key);
    };
    NSArray<UIButton *> *buttons=[overlay addChoiceButtons:options defaultIndex:defaultIndex select:selectIndex];
    if(guarded) {
        NSUInteger other=defaultIndex^1; if(other<buttons.count) buttons[other].enabled=NO;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(0.5*NSEC_PER_SEC)),dispatch_get_main_queue(),^{
            ready=YES; if(other<buttons.count)buttons[other].enabled=YES;
        });
    }
    overlay.hardwareKeyHandler=^BOOL(unichar key){
        if(key==' ' || key=='\r' || key=='\n') { selectIndex(defaultIndex); return YES; }
        if(key==27) {
            NSUInteger index=NSNotFound;
            for(NSUInteger i=0;i<options.count;i++) if([options[i] isEqual:@"q"]) { index=i; break; }
            if(index==NSNotFound) for(NSUInteger i=0;i<options.count;i++) if([options[i] isEqual:@"n"]) { index=i; break; }
            if(index==NSNotFound) {
                if(!defaultKey)return YES;
                NSUInteger fallback=NSNotFound;
                for(NSUInteger i=0;i<options.count;i++) if([options[i] characterAtIndex:0]==(unichar)defaultKey) { fallback=i; break; }
                if(fallback==NSNotFound) { [weakOverlay dismiss]; if(completion)completion(defaultKey); return YES; }
                index=fallback;
            }
            selectIndex(index); return YES;
        }
        for(NSUInteger i=0;i<options.count;i++) if([options[i] characterAtIndex:0]==key) { selectIndex(i); return YES; }
        return YES;
    };
    [overlay presentInView:self.view focusInput:NO];
    return overlay;
}
- (id)textDialog:(NSNumber *)wid {
    dispatch_semaphore_t ready=dispatch_semaphore_create(0);
    dispatch_async(dispatch_get_main_queue(),^{
        NSDictionary *window=self.windows[wid]; NSMutableArray<NSString *> *lines=[NSMutableArray new];
        for(NSDictionary *item in window[@"items"]) [lines addObject:item[@"text"] ?: @""];
        NHGurrOverlay *overlay=[self beginGameOverlay:window[@"title"] ?: @"NetHack"];
        [overlay addTextView:[lines componentsJoinedByString:@"\n"] height:260];
        __weak NHGurrOverlay *weakOverlay=overlay; __weak NHGame *weakSelf=self;
        overlay.onDismiss=^{ [weakSelf restoreGameControls]; dispatch_semaphore_signal(ready); };
        [overlay addActionWithTitle:@"OK" primary:YES handler:^{ [weakOverlay dismiss]; }];
        overlay.hardwareKeyHandler=^BOOL(unichar key){ [weakOverlay dismiss]; return YES; };
        [overlay presentInView:self.view focusInput:NO];
    });
    dispatch_semaphore_wait(ready,DISPATCH_TIME_FOREVER); return nil;
}
- (id)menu:(NSNumber *)wid how:(int)how {
    dispatch_semaphore_t ready=dispatch_semaphore_create(0); __block id result=nil;
    dispatch_async(dispatch_get_main_queue(),^{
        NSMutableDictionary *w=self.windows[wid];
        NHGurrOverlay *overlay=[self beginGameOverlay:w[@"title"] ?: @"NetHack"];
        NHMenu *menu=[NHMenu new]; menu.how=how; menu.title=w[@"title"] ?: @"NetHack"; menu.items=[w[@"items"] copy];
        menu.finish=^(id value){result=value; dispatch_semaphore_signal(ready);};
        menu.overlay=overlay; menu.tileImage=self.map.tiles; menu.tileSize=self.map.tileSize;
        [menu presentInView:self.view];
    }); dispatch_semaphore_wait(ready,DISPATCH_TIME_FOREVER); return result;
}
- (id)invoke:(NSString *)name arguments:(NSArray *)a {
    if([name isEqual:@"receiveKeyCmd"] || [name isEqual:@"receivePosKeyCmd"]) {
        BOOL pos=[name isEqual:@"receivePosKeyCmd"];
        if(!pos && [NSProcessInfo.processInfo.arguments containsObject:@"--ui-smoke"])return @32;
        dispatch_sync(dispatch_get_main_queue(),^{
            self.mouseLocked=pos && [a[0] boolValue]; self.waitingKey=!pos; self.moreButton.hidden=pos||self.expectsDirection;
            if(pos && self.map.cells.count && [NSProcessInfo.processInfo.arguments containsObject:@"--ui-smoke"]) {
                if(self.uiSmokeTurns++==0) {
                    NSCAssert(NHParsePanel(NHDefaultPanel).count==37,@"Default command panel changed");
                    NSCAssert(([NHCommandKeys(@"^dM-x20s") isEqual:@[@4,@248,@50,@48,@115]]),@"Command modifier parsing");
                    NSCAssert(([NHParsePanel(@"^d|Kick 20s|Search") isEqual:@[@[@"^d",@"Kick"],@[@"20s",@"Search"]]]),@"Command labels");
                    [self command:[self button:@"Wait" command:@"."]];
                } else if(self.uiSmokeTurns==2) {
                    NSCAssert([self.status.text containsString:@"HP:"],@"Missing hit points");
                    NSCAssert(self.keyboardLayouts.count==4 && self.panels.count==1,@"Missing Gurr controls");
                    [self writeUIReady:@"UI_READY"];
                    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,5*NSEC_PER_SEC),dispatch_get_main_queue(),^{
                        [self command:[self button:@"..." command:@"..."]]; [self.view layoutIfNeeded];
                        NSCAssert(!self.keyboardPanel.hidden && self.keyboardPanel.subviews.count>35,@"Keyboard did not open");
                        [self writeUIReady:@"UI_KEYBOARD"];
                        dispatch_after(dispatch_time(DISPATCH_TIME_NOW,5*NSEC_PER_SEC),dispatch_get_main_queue(),^{
                            [self showSettings];
                            dispatch_after(dispatch_time(DISPATCH_TIME_NOW,NSEC_PER_SEC),dispatch_get_main_queue(),^{
                                [self writeUIReady:@"UI_SETTINGS"];
                                dispatch_after(dispatch_time(DISPATCH_TIME_NOW,2*NSEC_PER_SEC),dispatch_get_main_queue(),^{
                                    if(self.presentedViewController) [self dismissViewControllerAnimated:NO completion:^{ [self runModalUISmokeSequence]; }];
                                    else [self runModalUISmokeSequence];
                                });
                            });
                        });
                    });
                }
            }
        });
        [self.inputCondition lock];
        NSArray *event=nil;
        do { while(!self.input.count)[self.inputCondition wait]; event=self.input.firstObject; [self.input removeObjectAtIndex:0]; } while(!pos && [event[0] intValue]==0);
        [self.inputCondition unlock];
        dispatch_sync(dispatch_get_main_queue(),^{ self.expectsDirection=NO; self.waitingKey=NO; self.moreButton.hidden=YES; [self updateDirectionOverlay]; if([event[0] intValue]==128)self.saveRequested=YES; });
        if([event[0] intValue]==0) { NHBuffer *b=a[1]; jint *p=b.data.mutableBytes; p[0]=[event[1] intValue]; p[1]=[event[2] intValue]; }
        return event[0];
    }
    if([name isEqual:@"askName"]) {
        NSString *last=[NSUserDefaults.standardUserDefaults stringForKey:@"player"] ?: @"Player";
        NSMutableArray *names=[[self promptHistoryForKey:@"playerHistory"] mutableCopy];
        id saves=a.count>1?a[1]:nil;
        if([saves isKindOfClass:NSArray.class]) {
            NSMutableArray *merged=[NSMutableArray new]; if(last.length)[merged addObject:last];
            for(id item in saves) if([item isKindOfClass:NSString.class] && [item length] && ![merged containsObject:item]) [merged addObject:item];
            for(NSString *item in names) if(![merged containsObject:item])[merged addObject:item];
            names=merged;
        }
        if(last.length && ![names containsObject:last]) [names insertObject:last atIndex:0];
        if(names.count) [NSUserDefaults.standardUserDefaults setObject:names forKey:@"playerHistory"];
        NSUInteger maxLength=a.count>0?MAX(1,[a[0] unsignedIntegerValue]):32;
        NSString *value=[self prompt:@"Who are you?" initial:last historyKey:@"playerHistory" maxLength:maxLength focusInput:NO];
        if(value.length && ![value isEqual:@"\033"]) [NSUserDefaults.standardUserDefaults setObject:value forKey:@"player"];
        return [value stringByAppendingString:@"0"];
    }
    if([name isEqual:@"getLine"]) {
        NSString *title=NHText(a[0]);
        if(a.count>2 && [a[2] boolValue] && self.history.count) {
            NSArray *recent=[self.history subarrayWithRange:NSMakeRange(MAX(0,(NSInteger)self.history.count-2),MIN(2,self.history.count))];
            title=[NSString stringWithFormat:@"%@\n%@",[recent componentsJoinedByString:@"\n"],title ?: @""];
        }
        NSUInteger maxLength=a.count>1?MAX(1,[a[1] unsignedIntegerValue]):200;
        return [self prompt:title initial:@"" historyKey:@"lineHistory" maxLength:maxLength focusInput:YES];
    }
    if([name isEqual:@"ynFunction"]) {
        NSString *question=NHText(a[0]),*choices=NHText(a[1]); int defaultKey=[a[2] intValue];
        dispatch_sync(dispatch_get_main_queue(),^{
            self.messages.text=[NSString stringWithFormat:@"%@ [%@]",question,choices];
            [self.view setNeedsLayout]; [self showQuestion:question choices:choices defaultKey:defaultKey completion:^(int key){ [self enqueue:@[@(key)]]; }];
            [self.messages scrollRangeToVisible:NSMakeRange(self.messages.text.length,0)];
        });
        return nil;
    }
    if([name isEqual:@"selectMenu"])return [self menu:a[0] how:[a[1] intValue]];
    if([name isEqual:@"getDumplogDir"])return @".";
    if([name isEqual:@"displayWindow"]) {
        __block BOOL text=NO;
        dispatch_sync(dispatch_get_main_queue(),^{ int t=[self.windows[a[0]][@"type"] intValue]; text=t==4||t==5; if(t==1 && self.saveRequested && [a[1] boolValue])[self enqueue:@[@32]]; });
        if(text) { id result=[self textDialog:a[0]]; [self enqueue:@[@32]]; return result; }
    }
    if([name isEqual:@"delayOutput"]) { [NSThread sleepForTimeInterval:0.03]; return nil; }
    __block id result=nil;
    dispatch_sync(dispatch_get_main_queue(),^{
        if([name isEqual:@"createWindow"]) { NSNumber *wid=@(++self.nextWindow); self.windows[wid]=[@{@"type":a[0],@"items":[NSMutableArray new],@"text":[NSMutableString new]} mutableCopy]; result=wid; }
        else if([name isEqual:@"destroyWindow"]) [self.windows removeObjectForKey:a[0]];
        else if([name isEqual:@"clearWindow"] || [name isEqual:@"startMenu"]) {
            NSMutableDictionary *w=self.windows[a[0]]; w[@"items"]=[NSMutableArray new]; w[@"text"]=[NSMutableString new];
            if([w[@"type"] intValue]==3) { [self.map.cells removeAllObjects]; [self.map setNeedsDisplay]; }
            if([w[@"type"] intValue]==2) { self.status.text=@""; [w removeObjectForKey:@"statusLines"]; }
        }
        else if([name isEqual:@"putString"] || [name isEqual:@"rawPrint"]) {
            BOOL raw=[name isEqual:@"rawPrint"]; NSString *s=NHText(a[raw?1:2]); NSMutableDictionary *w=raw?nil:self.windows[a[0]]; int type=[w[@"type"] intValue];
            if(type==2) { NSMutableArray *lines=w[@"statusLines"]; if(!lines) { lines=[NSMutableArray arrayWithObjects:[NSMutableAttributedString new],[NSMutableAttributedString new],nil]; w[@"statusLines"]=lines; } NSInteger row=[w[@"statusRow"] integerValue]; [lines[row] appendAttributedString:[[NSAttributedString alloc] initWithString:s attributes:@{NSForegroundColorAttributeName:NHColor([a[4] intValue])}]]; [self updateStatus:w]; }
            else if(type==4||type==5) [w[@"items"] addObject:@{@"id":@0,@"text":s}];
            else {
                if(raw || [a[3] intValue]==0) { [self.history addObject:s]; if(self.history.count>200)[self.history removeObjectAtIndex:0]; }
                else if(self.history.count) { NSString *last=self.history.lastObject; int append=[a[3] intValue]; if(append<0)last=[last substringToIndex:MAX(0,(NSInteger)last.length+append)]; self.history[self.history.count-1]=[last stringByAppendingString:s]; }
                self.messages.text=[self.history.lastObject copy] ?: @""; [self.view setNeedsLayout];
            }
        }
        else if([name isEqual:@"printTile"]) { int x=[a[1] intValue],y=[a[2] intValue]; self.map.cells[@(y*80+x)]=@[a[3],a[4],a[5],a[6]]; [self.map setNeedsDisplay]; }
        else if([name isEqual:@"setCursorPos"]) { NSMutableDictionary *w=self.windows[a[0]]; if([w[@"type"] intValue]==2) { NSInteger row=MAX(0,MIN(1,[a[2] integerValue])); w[@"statusRow"]=@(row); if(!w[@"statusLines"])w[@"statusLines"]=[NSMutableArray arrayWithObjects:[NSMutableAttributedString new],[NSMutableAttributedString new],nil]; w[@"statusLines"][row]=[NSMutableAttributedString new]; } if([self.windows[a[0]][@"type"] intValue]==3) { self.map.cursor=CGPointMake([a[1] intValue],[a[2] intValue]); [self.map setNeedsDisplay]; } }
        else if([name isEqual:@"cliparound"]) { self.player=CGPointMake([a[2] floatValue],[a[3] floatValue]); [self.map centerOnTile:CGPointMake([a[0] floatValue],[a[1] floatValue]) lockView:[NHPref(@"lockView",@YES) boolValue]]; }
        else if([name isEqual:@"addMenu"]) {
            id color=(a.count>8 && a[8]!=NSNull.null)?a[8]:@0;
            [self.windows[a[0]][@"items"] addObject:@{@"tile":a[1],@"id":a[2],@"acc":a[3],@"group":a[4],@"attr":a[5],@"text":NHText(a[6]),@"selected":a[7],@"color":color}];
        }
        else if([name isEqual:@"endMenu"]) self.windows[a[0]][@"title"]=NHText(a[1]);
        else if([name isEqual:@"setNumPadOption"]) { self.numpad=[a[0] boolValue]; [self applyPreferences]; }
        else if([name isEqual:@"askDirection"]) { self.expectsDirection=YES; [self updateDirectionOverlay]; }
        else if([name isEqual:@"copyText"]) UIPasteboard.generalPasteboard.string=NHText(a[0]);
        else if([name isEqual:@"debugLog"]) NSLog(@"NetHack: %@",NHText(a[0]));
    }); return result;
}
@end
id NHInvoke(NSString *name,NSArray *args) { return [game invoke:name arguments:args]; }

@interface NHApp : UIResponder <UIApplicationDelegate>
@property (nonatomic,strong) UIWindow *window;
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
