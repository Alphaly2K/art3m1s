package moe.alphaly.art3m1s

import android.app.Activity
import android.content.res.AssetManager
import android.util.Log

/** Supplies JNI, audio context and APK assets without requiring SDLActivity. */
internal class KrkrNativeBridge {
    private external fun nativeSetAssetManager(assets: AssetManager)

    companion object {
        private var initialized = false

        fun initialize(activity: Activity): Boolean {
            return try {
                System.loadLibrary("SDL3")
                System.loadLibrary("art3m1s_krkr_host")
                val sdl = Class.forName("org.libsdl.app.SDL")
                if (!initialized) {
                    sdl.getMethod("setupJNI").invoke(null)
                    sdl.getMethod("initialize").invoke(null)
                    initialized = true
                }
                sdl.getMethod("setContext", Activity::class.java).invoke(null, activity)
                KrkrNativeBridge().nativeSetAssetManager(activity.assets)
                true
            } catch (error: UnsatisfiedLinkError) {
                Log.i("Art3m1sKRKR", "KRKR native host is not packaged", error)
                false
            } catch (error: ReflectiveOperationException) {
                Log.e("Art3m1sKRKR", "SDL JNI initialization failed", error)
                false
            }
        }

        fun detach(activity: Activity) {
            if (!initialized) return
            try {
                val sdl = Class.forName("org.libsdl.app.SDL")
                if (sdl.getMethod("getContext").invoke(null) === activity) {
                    sdl.getMethod("setContext", Activity::class.java).invoke(null, null)
                }
            } catch (error: ReflectiveOperationException) {
                Log.w("Art3m1sKRKR", "SDL context release failed", error)
            }
        }
    }
}
