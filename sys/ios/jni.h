/* In-process compatibility surface for the Android window port.
 * No Java VM or Android runtime is involved. Only the used JNI subset exists. */
#ifndef NH_IOS_JNI_H
#define NH_IOS_JNI_H
#include <stdint.h>
typedef int jint;
typedef int64_t jlong;
typedef unsigned short jchar;
typedef signed char jbyte;
typedef unsigned char jboolean;
typedef void *jobject;
typedef jobject jclass, jstring, jbyteArray, jintArray, jlongArray, jobjectArray;
typedef struct NHMethod *jmethodID;
typedef const struct NHJNI *JNIEnv;
struct NHJNI {
    jclass (*GetObjectClass)(JNIEnv *, jobject);
    jclass (*FindClass)(JNIEnv *, const char *);
    jmethodID (*GetMethodID)(JNIEnv *, jclass, const char *, const char *);
    void (*CallVoidMethod)(JNIEnv *, jobject, jmethodID, ...);
    jint (*CallIntMethod)(JNIEnv *, jobject, jmethodID, ...);
    jobject (*CallObjectMethod)(JNIEnv *, jobject, jmethodID, ...);
    jbyteArray (*NewByteArray)(JNIEnv *, jint);
    jintArray (*NewIntArray)(JNIEnv *, jint);
    jbyte *(*GetByteArrayElements)(JNIEnv *, jbyteArray, jboolean *);
    jint *(*GetIntArrayElements)(JNIEnv *, jintArray, jboolean *);
    jlong *(*GetLongArrayElements)(JNIEnv *, jlongArray, jboolean *);
    void (*ReleaseByteArrayElements)(JNIEnv *, jbyteArray, jbyte *, jint);
    void (*ReleaseIntArrayElements)(JNIEnv *, jintArray, jint *, jint);
    void (*ReleaseLongArrayElements)(JNIEnv *, jlongArray, jlong *, jint);
    jint (*GetArrayLength)(JNIEnv *, jobject);
    void (*DeleteLocalRef)(JNIEnv *, jobject);
    const char *(*GetStringUTFChars)(JNIEnv *, jstring, jboolean *);
    void (*ReleaseStringUTFChars)(JNIEnv *, jstring, const char *);
    const jchar *(*GetStringChars)(JNIEnv *, jstring, jboolean *);
    void (*ReleaseStringChars)(JNIEnv *, jstring, const jchar *);
    jint (*GetStringLength)(JNIEnv *, jstring);
    jstring (*NewStringUTF)(JNIEnv *, const char *);
    jobjectArray (*NewObjectArray)(JNIEnv *, jint, jclass, jobject);
    void (*SetObjectArrayElement)(JNIEnv *, jobjectArray, jint, jobject);
    jobject (*GetObjectArrayElement)(JNIEnv *, jobjectArray, jint);
};
void NHRun(const char *directory);
#endif
