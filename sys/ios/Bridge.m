#import "Bridge.h"
#include <stdarg.h>

@implementation NHBuffer
+ (instancetype)count:(NSUInteger)n size:(NSUInteger)s {
    NHBuffer *b = [NHBuffer new]; b.elementSize = s;
    b.data = [NSMutableData dataWithLength:n*s]; return b;
}
@end
NSString *NHText(id value) {
    if ([value isKindOfClass:NSString.class]) return value;
    if ([value isKindOfClass:NHBuffer.class]) {
        NSData *d = [value data];
        NSString *s = [[NSString alloc] initWithData:d encoding:NSUTF8StringEncoding];
        return s ?: [[NSString alloc] initWithData:d encoding:NSISOLatin1StringEncoding] ?: @"";
    }
    return @"";
}
void NHCopyText(const char *text) { NHInvoke(@"copyText", @[@(text ?: "")]); }
struct NHMethod { const char *name; const char *signature; };
static id obj(jobject p) { return (__bridge id)p; }
static jobject keep(id o) { return o ? (void *)CFBridgingRetain(o) : NULL; }
static void drop(JNIEnv *e, jobject p) { if (p) CFRelease(p); }
static jclass cls(JNIEnv *e, jobject p) { return NULL; }
static jclass find(JNIEnv *e, const char *n) { return NULL; }
static jmethodID method(JNIEnv *e, jclass c, const char *n, const char *s) {
    struct NHMethod *m = calloc(1, sizeof(*m)); m->name=n; m->signature=s; return m;
}
static NSArray *arguments(jmethodID m, va_list ap) {
    NSMutableArray *a=[NSMutableArray new];
    const char *p=m->signature+1;
    while (*p && *p!=')') {
        if (*p=='I') { [a addObject:@(va_arg(ap,int))]; ++p; }
        else if (*p=='J') { [a addObject:@(va_arg(ap,jlong))]; ++p; }
        else {
            [a addObject:obj(va_arg(ap,jobject)) ?: NSNull.null];
            while (*p=='[') ++p;
            if (*p=='L') { while (*p && *p!=';') ++p; }
            if (*p) ++p;
        }
    }
    return a;
}
static void callV(JNIEnv *e,jobject o,jmethodID m,...) {
    @autoreleasepool { va_list ap; va_start(ap,m); NSArray *a=arguments(m,ap); va_end(ap); NHInvoke(@(m->name),a); }
}
static jint callI(JNIEnv *e,jobject o,jmethodID m,...) {
    @autoreleasepool { va_list ap; va_start(ap,m); NSArray *a=arguments(m,ap); va_end(ap); return [NHInvoke(@(m->name),a) intValue]; }
}
static jobject callO(JNIEnv *e,jobject o,jmethodID m,...) {
    @autoreleasepool { va_list ap; va_start(ap,m); NSArray *a=arguments(m,ap); va_end(ap); return keep(NHInvoke(@(m->name),a)); }
}
static jobject bytes(JNIEnv *e,jint n) { return keep([NHBuffer count:n size:1]); }
static jobject ints(JNIEnv *e,jint n) { return keep([NHBuffer count:n size:sizeof(jint)]); }
static jbyte *getB(JNIEnv *e,jobject a,jboolean *b) { return [((NHBuffer *)obj(a)).data mutableBytes]; }
static jint *getI(JNIEnv *e,jobject a,jboolean *b) { return [((NHBuffer *)obj(a)).data mutableBytes]; }
static jlong *getL(JNIEnv *e,jobject a,jboolean *b) { return [((NHBuffer *)obj(a)).data mutableBytes]; }
static void relB(JNIEnv *e,jobject a,jbyte *p,jint m) {}
static void relI(JNIEnv *e,jobject a,jint *p,jint m) {}
static void relL(JNIEnv *e,jobject a,jlong *p,jint m) {}
static jint length(JNIEnv *e,jobject a) { NHBuffer *b=obj(a); return (jint)(b.data.length/b.elementSize); }
static const char *utf(JNIEnv *e,jstring a,jboolean *b) { return [obj(a) UTF8String]; }
static void relUTF(JNIEnv *e,jstring a,const char *p) {}
static jint strlen16(JNIEnv *e,jstring a) { return (jint)[obj(a) length]; }
static const jchar *chars(JNIEnv *e,jstring a,jboolean *b) {
    NSString *s=obj(a); jchar *p=calloc(s.length+1,sizeof(jchar));
    [s getCharacters:p range:NSMakeRange(0,s.length)]; return p;
}
static void relChars(JNIEnv *e,jstring a,const jchar *p) { free((void *)p); }
static jstring string(JNIEnv *e,const char *s) { return keep(@(s ?: "")); }
static jobjectArray array(JNIEnv *e,jint n,jclass c,jobject v) {
    NSMutableArray *a=[NSMutableArray new]; for(int i=0;i<n;i++) [a addObject:obj(v) ?: NSNull.null]; return keep(a);
}
static void set(JNIEnv *e,jobjectArray a,jint i,jobject v) { ((NSMutableArray *)obj(a))[i]=obj(v); drop(e,v); }
static jobject get(JNIEnv *e,jobjectArray a,jint i) { return keep(((NSArray *)obj(a))[i]); }
static const struct NHJNI table={
    cls,find,method,callV,callI,callO,bytes,ints,getB,getI,getL,relB,relI,relL,
    length,drop,utf,relUTF,chars,relChars,strlen16,string,array,set,get
};
extern void Java_com_tbd_forkfront_NetHackIO_RunNetHack(JNIEnv *,jobject,jstring,jstring);
void NHRun(const char *directory) {
    @autoreleasepool {
        JNIEnv e=&table; jobject path=string(&e,directory);
        Java_com_tbd_forkfront_NetHackIO_RunNetHack(&e,NULL,path,NULL);
        drop(&e,path);
    }
}
