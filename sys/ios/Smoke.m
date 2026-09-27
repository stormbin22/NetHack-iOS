/* Exercise the actual engine and bridge without UIKit, on the macOS builder. */
#import "Bridge.h"
static NSMutableDictionary *menus;
static int nextWindow, moves, keys, pending;
static BOOL drewMap, restored;
id NHInvoke(NSString *name,NSArray *a) {
    if([name isEqual:@"createWindow"])return @(++nextWindow);
    if([name isEqual:@"askName"])return @"PortTest0";
    if([name isEqual:@"getLine"])return @"";
    if([name isEqual:@"startMenu"])menus[a[0]]=[NSMutableArray new];
    if([name isEqual:@"addMenu"] && [a[2] longLongValue]) [menus[a[0]] addObject:a[2]];
    if([name isEqual:@"selectMenu"]) {
        NSArray *items=menus[a[0]];
        NHBuffer *b=[NHBuffer count:items.count && [a[1] intValue] ? 2:0 size:sizeof(jlong)];
        if(b.data.length) { jlong *p=b.data.mutableBytes; p[0]=[items[0] longLongValue]; p[1]=-1; } return b;
    }
    if([name isEqual:@"ynFunction"]) {
        NSString *choices=NHText(a[1]); pending=[choices containsString:@"y"]?'y':[a[2] intValue];
        if(!pending)pending=27;
    }
    if([name isEqual:@"receiveKeyCmd"]) { if(++keys>300) { fprintf(stderr,"Too many key requests\n"); exit(3); } int key=pending ?: ' '; pending=0; return @(key); }
    if([name isEqual:@"receivePosKeyCmd"]) { ++moves; return @(moves<=4 ? '.' : 128); }
    if([name isEqual:@"printTile"])drewMap=YES;
    if([name isEqual:@"rawPrint"] || [name isEqual:@"putString"] || [name isEqual:@"debugLog"]) {
        NSString *s=NHText(a[[name isEqual:@"putString"]?2:([name isEqual:@"rawPrint"]?1:0)]);
        if([s containsString:@"Restoring save file"])restored=YES;
        fprintf(stdout,"%s\n",s.UTF8String); fflush(stdout);
    }
    if([name isEqual:@"getDumplogDir"])return @".";
    return nil;
}
int main(int argc,char **argv) { @autoreleasepool {
    if(argc<2)return 2; menus=[NSMutableDictionary new]; NHRun(argv[1]);
    if(!drewMap || moves<5) { fprintf(stderr,"Engine did not reach gameplay\n"); return 4; }
    if(argc>2 && !restored) { fprintf(stderr,"Saved game was not restored\n"); return 5; }
    puts("PASS: map rendered, four turns processed, engine save/exit completed"); return 0;
} }
