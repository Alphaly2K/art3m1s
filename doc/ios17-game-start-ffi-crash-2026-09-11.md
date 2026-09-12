# iOS 17.3 game-start FFI callback crash

## Status

The native-first app now opens on the reported device. The new crash is during
game-page construction, while media_kit prewarms its first mpv player. The
immediate fault is execution of a Dart FFI callback trampoline whose mapping
lacks execute permission. No production runtime workaround has been applied.
The reason that mapping lost execute permission is not established by this report.

## Matching artifacts

- Report: `/Users/alphaly/Downloads/Runner-2026-09-11-220004.ips`
- Device: iPad11,1; iOS 17.3 (21D50).
- App launched at 21:59:50.2752, crashed at 22:00:03.8787 (+0800).
- Build: `build/ios/native-entry-20260911/Profile-iphoneos/Runner.app`.
- IPA: `Downloads/Art3m1s-1.3.0-native-profile-20260911.ipa`.
- Runner UUID: `6E99A7C3-3951-3170-B9D8-507878059F91`.
- Art3m1sRuntime UUID: `53B57055-888D-3B5D-B3F1-323F3D37CA9E`.
- App UUID: `8228BCF3-66C2-5A0E-A30D-B0EB47FB464A`.
- Mpv UUID: `80555C75-73AD-3589-95F6-777ADA0D8FD4`.

The build's App.framework.dSYM matches the report. This is essential: the
Runner/Runtime dSYMs alone cannot identify the Dart call chain. Packaging now
requires and preserves App.framework.dSYM alongside them.

## Symbolicated chain

App image-relative return addresses, from the innermost Dart frame outward:

| Offset | Symbol |
| --- | --- |
| 0x9608 | stub CallNativeThroughSafepoint + 88 |
| 0x21a28 | MPV._mpv_set_wakeup_callback.#ffiClosure41 |
| 0x2392c | MPV.mpv_set_wakeup_callback (bindings.dart:1405) |
| 0x1f96c4 | InitializerNativeCallable.create |
| 0x1fa6dc | Initializer.create |
| 0x1f861c | NativePlayer._create anonymous closure |
| 0x4760b4 | BasicLock.synchronized |
| 0x1f8534 | NativePlayer._create |
| 0x1f8428 | new NativePlayer |
| 0x203494 | new Player |
| 0x2038d4 | MediaKitVideoPool._createLease |
| 0x206238 | MediaKitVideoPool._createAndStoreLease |
| 0x206320 | MediaKitVideoPool._warm |
| 0x206458 | MediaKitVideoPool.prewarm |
| 0x216bb8 | new MediaBridge |
| 0x217804 | CoreBridge.media |

Reproduce with the matching build directory as the working directory:

```sh
xcrun dwarfdump --uuid App.framework.dSYM
xcrun atos -arch arm64 \
  -o App.framework.dSYM/Contents/Resources/DWARF/App -l 0 \
  0x9608 0x21a28 0x2392c 0x1f96c4 0x1fa6dc 0x1f861c \
  0x4760b4 0x1f8534 0x1f8428 0x203494 0x2038d4 \
  0x206238 0x206320 0x206458 0x216bb8 0x217804
xcrun atos -arch arm64 -o Runner.app/Frameworks/Mpv.framework/Mpv \
  -l 0x107720000 0x10778abf4 0x10778abf0
```

## Native evidence

Main-thread registers:

```text
PC = FAR = x1 = x20 = 0x10af215ac
LR                  = 0x10778abf4
Mpv load base       = 0x107720000
LR - Mpv base       = 0x6abf4 = mpv_set_wakeup_callback + 56
```

The matching Mpv binary contains:

```text
0x6abd0  mov x20, x1          // supplied callback
0x6abe4  stp x20, x21, [x22, #0x140]
0x6abe8  cbz x20, 0x6abf4
0x6abec  mov x0, x21          // callback userdata
0x6abf0  blr x20              // immediate callback invocation
0x6abf4  mov x0, x19          // reported LR
```

The exception is `EXC_BAD_ACCESS / SIGBUS / KERN_PROTECTION_FAILURE`.
The report describes an instruction abort, not a failed read of game data:

```text
0x10af20000-0x10af28000 [32K] mapped file r--/rw- SM=COW
```

Neither current nor maximum protection includes execute. The callback is
0x15ac bytes into this mapping. The matching App dSYM places
`stub FfiCallbackTrampoline` at 0x55ac, also 0x15ac past its 16 KiB page start
(0x4000). This exactly matches the first trampoline in a remapped Dart callback
page. The unknown image index 40 is a zero-base placeholder, not another dylib.

media_kit 1.2.6 creates a `NativeCallable.listener`, retains it, then immediately
calls `mpv_set_wakeup_callback`. The callback has not been disposed at this point.
The mpv worker thread is idle; its presence alone is not the basis of this finding.

## Runtime implications

Dart 3.12.2's `FfiCallbackMetadata::AllocateTrampolinePage` uses
`VirtualMemory::DuplicateRX` on precompiled Apple targets. `DuplicateRX` calls
`vm_remap` with copy=true. It tests the return status, but its protection checks
are assertions. The actual delivered Profile Flutter disassembly also checks
the remap status without validating the returned protection bits.

Relevant upstream sources:

- https://github.com/dart-lang/sdk/blob/3.12.2/runtime/vm/ffi_callback_metadata.cc
- https://github.com/dart-lang/sdk/blob/3.12.2/runtime/vm/virtual_memory_posix.cc
- https://github.com/dart-lang/sdk/blob/3.12.2/runtime/vm/isolate.cc

This evidence supports a callback-page mapping/protection failure. It does not
show whether vm_remap returned incorrect permissions initially or another
component changed the mapping afterwards.

The report includes systemhook, roothideinit, libroothide, roothidepatch,
AutoPatches, libellekit, AppHider and TrollPadUI. Their presence establishes an
injected environment, not which component caused the fault. No official iOS
system-symbol offsets were used to infer the mpv/Dart call sites.

The game's CoreBridge and FileProvider use `NativeCallable.isolateLocal`, and
layer video uses another `NativeCallable.listener`. Dart routes these through
the same callback metadata/page allocator. Removing prewarm, or selecting
media_kit's isolate event loop alone, would leave those other call sites exposed.
Changing to Pointer.fromFunction should not be assumed to fix this without
checking its generated callback path on the exact Dart version.

## Next discriminating check

Use the same IPA and game with optional tweak injection disabled for this app,
then fully terminate and relaunch it. This requires no new diagnostic build and
does not change the native-first startup path. Record which RootHide/base hooks
remain active: disabling optional tweaks may not disable the base compatibility
layer. A successful game launch would implicate the injection configuration; a
failure would not by itself rule out the base layer.

If the fault persists, investigate callback allocation/remapping with the actual
device environment. A production fix must cover all native-to-Dart callbacks.
Do not blindly add executable entitlements, mprotect arbitrary memory, or replace
the media package based only on the top-level plugin name. The reported mapping
also lacks execute in its maximum permissions, so a simple RX permission flip
cannot be presumed to succeed.

No runtime fix or new test build was produced for this finding. Native-first
startup, logging limits, texture rendering and file-access behavior remain as
previously committed. The existing build was repackaged locally solely to verify
symbol preservation and signing; all three matching dSYMs are retained under
`build/ios/game-crash-evidence-20260911/Art3m1s-native-profile-symbols.dSYMs`.
The six existing native-manifest tests and the real packaging/signature checks
passed. This is packaging validation, not verification of game playback on the
affected device.
