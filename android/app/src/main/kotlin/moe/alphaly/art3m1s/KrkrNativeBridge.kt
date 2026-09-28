package moe.alphaly.art3m1s

import android.content.res.AssetManager
import android.util.Log

/** Supplies APK assets to the embedded KRKRSDL3 runtime without SDLActivity. */
internal class KrkrNativeBridge {
    private external fun nativeSetAssetManager(assets: AssetManager)

    companion object {
        fun initialize(assets: AssetManager) {
            try {
                System.loadLibrary("SDL3")
                System.loadLibrary("art3m1s_krkr_host")
                KrkrNativeBridge().nativeSetAssetManager(assets)
            } catch (error: UnsatisfiedLinkError) {
                // Normal Android builds intentionally omit the optional KRKR backend.
                Log.i("Art3m1sKRKR", "KRKR native host is not packaged", error)
            }
        }
    }
}
