#import <UIKit/UIKit.h>
#import "Bridge.h"
#import "GurrUI.h"

static UIColor *NHColor(int rgb) {
    return [UIColor colorWithRed:((rgb>>16)&255)/255.0 green:((rgb>>8)&255)/255.0 blue:(rgb&255)/255.0 alpha:1];
}
@interface NHMap : UIView
@property NSMutableDictionary<NSNumber *,NSArray *> *cells;
@property UIImage *tiles;
@property CGSize tileSize;
@property CGPoint cursor;
@end
@implementation NHMap
- (instancetype)init {
    if ((self=[super initWithFrame:CGRectMake(0,0,80*24,21*24)])) {
        self.cells=[NSMutableDictionary new]; self.backgroundColor=UIColor.blackColor;
        self.tiles=[UIImage imageWithContentsOfFile:[NSBundle.mainBundle pathForResource:@"default_16x16" ofType:@"png"]];
        self.cursor=CGPointMake(-1,-1); self.tileSize=CGSizeMake(16,16);
    } return self;
}
- (void)drawRect:(CGRect)rect {
    CGContextRef ctx=UIGraphicsGetCurrentContext(); CGContextSetInterpolationQuality(ctx,kCGInterpolationNone);
    for (NSNumber *key in self.cells) {
        int k=key.intValue; CGRect r=CGRectMake((k%80)*24,(k/80)*24,24,24);
        if (!CGRectIntersectsRect(rect,r)) continue;
        NSArray *v=self.cells[key]; int tile=[v[0] intValue];
        int tw=MAX(1,self.tileSize.width),th=MAX(1,self.tileSize.height); int cols=(int)self.tiles.size.width/tw, rows=(int)self.tiles.size.height/th;
        if (cols>0 && tile>=0 && tile<cols*rows) {
            CGImageRef crop=CGImageCreateWithImageInRect(self.tiles.CGImage,CGRectMake((tile%cols)*tw,(tile/cols)*th,tw,th));
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
    [super viewDidLoad]; self.overrideUserInterfaceStyle=UIUserInterfaceStyleDark; self.selection=[NSMutableDictionary new];
    UILongPressGestureRecognizer *quantity=[[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(quantity:)]; [self.tableView addGestureRecognizer:quantity];
    for(NSDictionary *item in self.items) if([item[@"selected"] boolValue] && [item[@"id"] longLongValue]) self.selection[item[@"id"]]=@(-1);
    self.navigationItem.leftBarButtonItem=[[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemCancel target:self action:@selector(cancel)];
    self.navigationItem.rightBarButtonItem=[[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemDone target:self action:@selector(done)];
    self.tableView.allowsMultipleSelection=self.how==2;
}
- (void)complete:(id)value { void (^callback)(id)=self.finish; self.finish=nil; [self dismissViewControllerAnimated:YES completion:^{ if(callback)callback(value); }]; }
- (void)cancel { [self complete:nil]; }
- (void)quantity:(UILongPressGestureRecognizer *)press {
    if(press.state!=UIGestureRecognizerStateBegan || !self.how)return;
    NSIndexPath *path=[self.tableView indexPathForRowAtPoint:[press locationInView:self.tableView]]; if(!path)return;
    NSDictionary *item=self.items[path.row]; NSNumber *ident=item[@"id"]; if(!ident.longLongValue)return;
    UIAlertController *a=[UIAlertController alertControllerWithTitle:@"Quantity" message:item[@"text"] preferredStyle:UIAlertControllerStyleAlert];
    [a addTextFieldWithConfigurationHandler:^(UITextField *f){ f.keyboardType=UIKeyboardTypeNumberPad; f.placeholder=@"All"; }];
    [a addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [a addAction:[UIAlertAction actionWithTitle:@"Select" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action){
        long long count=a.textFields.firstObject.text.longLongValue; if(self.how==1)[self.selection removeAllObjects]; self.selection[ident]=count>0?@(count):@(-1);
        [a dismissViewControllerAnimated:YES completion:^{ if(self.how==1)[self done]; else [self.tableView reloadData]; }];
    }]];
    [self presentViewController:a animated:YES completion:nil];
}
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
@property NSMutableArray<UIScrollView *> *panels;
@property NSMutableArray<NSDictionary *> *panelDefinitions;
@property NSMutableArray<NSString *> *history;
@property UIView *keyboardPanel, *dpad;
@property NHCommandButton *moreButton;
@property NSDictionary *keyboardLayouts;
@property NSString *keyboardMode;
@property BOOL shift, lastLandscape, waitingKey;
@property NSInteger uiSmokeTurns;

- (void)enqueue:(NSArray *)event;
- (id)invoke:(NSString *)name arguments:(NSArray *)args;
@end
static NHGame *game;
@implementation NHGame
#include "GurrFrontend.inc"
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
- (void)mapTap:(UITapGestureRecognizer *)tap { CGPoint p=[tap locationInView:self.map]; [self touch:p longPress:NO]; }
- (void)mapHold:(UILongPressGestureRecognizer *)hold { if(hold.state==UIGestureRecognizerStateBegan)[self touch:[hold locationInView:self.map] longPress:YES]; }
- (void)touch:(CGPoint)p longPress:(BOOL)hold {
    int x=(int)(p.x/24),y=(int)(p.y/24); if(x<1||x>=80||y<0||y>=21)return;
    CGFloat dx=p.x-(self.player.x+0.5)*24,dy=p.y-(self.player.y+0.5)*24;
    CGFloat z=self.scroll.zoomScale;
    BOOL onSelf=(x==(int)self.player.x && y==(int)self.player.y) || (dx*dx+dy*dy)*z*z<25*25;
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
- (id)prompt:(NSString *)title initial:(NSString *)initial {
    dispatch_semaphore_t ready=dispatch_semaphore_create(0); __block NSString *answer=nil;
    dispatch_async(dispatch_get_main_queue(),^{
        [self.keyboard resignFirstResponder];
        UIAlertController *alert=[UIAlertController alertControllerWithTitle:title message:nil preferredStyle:UIAlertControllerStyleAlert];
        [alert addTextFieldWithConfigurationHandler:^(UITextField *f){ f.text=initial; f.autocapitalizationType=UITextAutocapitalizationTypeNone; f.autocorrectionType=UITextAutocorrectionTypeNo; f.keyboardType=UIKeyboardTypeASCIICapable; }];
        [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:^(UIAlertAction *a){ answer=@"\033"; [alert dismissViewControllerAnimated:YES completion:^{dispatch_semaphore_signal(ready);}]; }]];
        [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a){ answer=alert.textFields.firstObject.text ?: @""; [alert dismissViewControllerAnimated:YES completion:^{dispatch_semaphore_signal(ready);}]; }]];
        [self presentViewController:alert animated:YES completion:nil];
    }); dispatch_semaphore_wait(ready,DISPATCH_TIME_FOREVER); return answer;
}
- (id)menu:(NSNumber *)wid how:(int)how {
    dispatch_semaphore_t ready=dispatch_semaphore_create(0); __block id result=nil;
    dispatch_async(dispatch_get_main_queue(),^{
        [self.keyboard resignFirstResponder]; NSMutableDictionary *w=self.windows[wid];
        NHMenu *menu=[NHMenu new]; menu.how=how; menu.title=w[@"title"] ?: @"NetHack"; menu.items=[w[@"items"] copy];
        menu.finish=^(id value){result=value; dispatch_semaphore_signal(ready);};
        UINavigationController *nav=[[UINavigationController alloc] initWithRootViewController:menu]; nav.modalPresentationStyle=UIModalPresentationFullScreen; nav.overrideUserInterfaceStyle=UIUserInterfaceStyleDark;
        [self presentViewController:nav animated:YES completion:nil];
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
                            dispatch_after(dispatch_time(DISPATCH_TIME_NOW,NSEC_PER_SEC),dispatch_get_main_queue(),^{ [self writeUIReady:@"UI_SETTINGS"]; });
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
        else if([name isEqual:@"cliparound"]) { self.player=CGPointMake([a[2] floatValue],[a[3] floatValue]); CGFloat z=self.scroll.zoomScale; CGPoint p=CGPointMake([a[0] floatValue]*24*z-self.scroll.bounds.size.width/2,[a[1] floatValue]*24*z-self.scroll.bounds.size.height/2); p.x=MAX(0,MIN(p.x,self.scroll.contentSize.width-self.scroll.bounds.size.width)); p.y=MAX(0,MIN(p.y,self.scroll.contentSize.height-self.scroll.bounds.size.height)); if([NHPref(@"lockView",@YES) boolValue]) { if(self.scroll.contentSize.width<=self.scroll.bounds.size.width)p.x=0; if(self.scroll.contentSize.height<=self.scroll.bounds.size.height)p.y=0; } [self.scroll setContentOffset:p animated:NO]; }
        else if([name isEqual:@"addMenu"]) [self.windows[a[0]][@"items"] addObject:@{@"id":a[2],@"text":NHText(a[6]),@"selected":a[7]}];
        else if([name isEqual:@"endMenu"]) self.windows[a[0]][@"title"]=NHText(a[1]);
        else if([name isEqual:@"ynFunction"]) { self.messages.text=[NSString stringWithFormat:@"%@ [%@]",NHText(a[0]),NHText(a[1])]; [self.view setNeedsLayout]; self.keyboardPanel.hidden=NO; [self.messages scrollRangeToVisible:NSMakeRange(self.messages.text.length,0)]; }
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
