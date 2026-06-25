plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// ── NDK libc++_shared.so 打包 ──────────────────────────────────────────────
// art3m1s-core 通过 build.rs 链接 c++_shared（FFmpeg 需要 C++ ABI 符号）。
// 必须把 NDK 自带的 libc++_shared.so 打进 APK，否则运行时会报
// "cannot locate symbol __cxa_pure_virtual"。
fun ndkHostTag(): String {
    val os = System.getProperty("os.name").lowercase()
    val arch = System.getProperty("os.arch").lowercase()
    val hostOs = when {
        os.contains("mac") || os.contains("darwin") -> "darwin"
        os.contains("linux") -> "linux"
        os.contains("win") -> "windows"
        else -> error("Unsupported host OS: $os")
    }
    val hostArch = when {
        arch.contains("x86_64") || arch.contains("amd64") -> "x86_64"
        arch.contains("aarch64") || arch.contains("arm64") -> "arm64"
        else -> error("Unsupported host arch: $arch")
    }
    return "$hostOs-$hostArch"
}

fun abiToNdkTriple(abi: String): String = when (abi) {
    "arm64-v8a" -> "aarch64-linux-android"
    "armeabi-v7a" -> "arm-linux-androideabi"
    "x86_64" -> "x86_64-linux-android"
    "x86" -> "i686-linux-android"
    else -> error("Unsupported ABI: $abi")
}

android {
    namespace = "moe.alphaly.art3m1s"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    // 编译 art3m1s_jni.so（JNI_OnLoad 存 JavaVM，提供 getVmPtr 给 Kotlin）。
    externalNativeBuild {
        cmake {
            path = file("src/main/cpp/CMakeLists.txt")
            version = "3.22.1"
        }
    }

    defaultConfig {
        // TODO: Specify your own unique application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "moe.alphaly.art3m1s"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

// 把 NDK 的 libc++_shared.so 拷贝到 jniLibs 目录，让 Gradle 打进 APK。
// 关键：srcDir 必须在配置阶段注册（Gradle 在配置阶段解析输入目录），
// 拷贝动作通过 dependsOn 保证在 mergeJniLibs 之前发生。
android.applicationVariants.all {
    val variant = this
    val jniLibsBase = layout.buildDirectory.dir("intermediates/art3m1s-jni/${variant.name}").get().asFile
    // 配置阶段注册 srcDir —— Gradle 此时解析 mergeJniLibs 的输入目录
    android.sourceSets.getByName(variant.name).jniLibs.srcDir(jniLibsBase)
    val mergeJniLibs = tasks.findByName("merge${variant.name.replaceFirstChar { it.uppercase() }}JniLibs")
    val copyCppShared = tasks.register("copyCppShared${variant.name.replaceFirstChar { it.uppercase() }}") {
        doLast {
            val ndkDir = android.ndkDirectory
            val hostTag = ndkHostTag()
            val abiFilters = android.defaultConfig.ndk.abiFilters ?: setOf("arm64-v8a")
            abiFilters.forEach { abi ->
                val triple = abiToNdkTriple(abi)
                val src = ndkDir.resolve("toolchains/llvm/prebuilt/$hostTag/$triple/lib/libc++_shared.so")
                val dst = jniLibsBase.resolve("$abi/libc++_shared.so")
                if (src.exists()) {
                    dst.parentFile.mkdirs()
                    src.copyTo(dst, overwrite = true)
                } else {
                    logger.warn("libc++_shared.so not found at: $src")
                }
            }
        }
    }
    mergeJniLibs?.dependsOn(copyCppShared)
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}

dependencies {
    // SAF DocumentFile：pickDirectoryAndCopy 用来递归拷贝用户选中的目录。
    implementation("androidx.documentfile:documentfile:1.1.0")
}
