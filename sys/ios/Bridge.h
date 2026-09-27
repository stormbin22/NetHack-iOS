#import <Foundation/Foundation.h>
#import "jni.h"
@interface NHBuffer : NSObject
@property NSMutableData *data;
@property NSUInteger elementSize;
+ (instancetype)count:(NSUInteger)count size:(NSUInteger)size;
@end
// Invoked on the engine thread. UIKit implementations marshal onto main.
id NHInvoke(NSString *name, NSArray *arguments);
NSString *NHText(id value);
