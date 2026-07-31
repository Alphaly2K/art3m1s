// art3m1s_jni.cpp — 最小 JNI 胶水：
// - JNI_OnLoad 存 JavaVM
// - nativeGetVmPtr() 返回 JavaVM 指针
// - nativeRegisterContext(Context) 创建全局引用，存下 jobject 指针并返回

#include <jni.h>
#include <android/native_window_jni.h>

static JavaVM *g_vm = nullptr;
static jobject g_context = nullptr;

extern "C" JNIEXPORT jint JNICALL JNI_OnLoad(JavaVM *vm, void * /*reserved*/) {
    g_vm = vm;
    return JNI_VERSION_1_6;
}

extern "C" JNIEXPORT jlong JNICALL
Java_moe_alphaly_art3m1s_MainActivity_nativeGetVmPtr(JNIEnv * /*env*/, jclass /*clazz*/) {
    return reinterpret_cast<jlong>(g_vm);
}

// 把 Activity/Application Context 存为全局引用，返回 jobject 指针值。
// Rust 侧 ndk-context 只需要 (JavaVM*, jobject) 这对值。
extern "C" JNIEXPORT jlong JNICALL
Java_moe_alphaly_art3m1s_MainActivity_nativeRegisterContext(JNIEnv *env, jclass /*clazz*/, jobject ctx) {
    if (ctx == nullptr) return 0;
    if (g_context == nullptr) {
        g_context = env->NewGlobalRef(ctx);
    }
    return reinterpret_cast<jlong>(g_context);
}

extern "C" JNIEXPORT jlong JNICALL
Java_moe_alphaly_art3m1s_MainActivity_nativeAcquireSurfaceWindow(
        JNIEnv *env, jclass /*clazz*/, jobject surface) {
    if (surface == nullptr) return 0;
    return reinterpret_cast<jlong>(ANativeWindow_fromSurface(env, surface));
}

extern "C" JNIEXPORT void JNICALL
Java_moe_alphaly_art3m1s_MainActivity_nativeReleaseSurfaceWindow(
        JNIEnv * /*env*/, jclass /*clazz*/, jlong window) {
    if (window != 0) {
        ANativeWindow_release(reinterpret_cast<ANativeWindow *>(window));
    }
}
