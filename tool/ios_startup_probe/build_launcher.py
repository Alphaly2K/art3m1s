"""Extend the native Probe with deferred Runner loading and a real Flutter UI."""

import argparse
import hashlib
import json
from pathlib import Path
import plistlib
import shutil
import sys
import tempfile

import lief

from build import binary_uuid, run


def payload_state(binary):
    if not binary.has_dyld_info or binary.has_dyld_chained_fixups:
        raise ValueError("Expected a Runner with classic dyld binding information")
    return {
        "sections": [
            (item.segment_name, item.name, item.virtual_address, item.offset,
             item.size, hashlib.sha256(bytes(item.content)).hexdigest())
            for item in binary.sections
        ],
        "dependencies": [(item.name, item.command) for item in binary.libraries
                         if item.command != lief.MachO.LoadCommand.TYPE.ID_DYLIB],
        "rpaths": [item.path for item in binary.rpaths],
        "bindings": [(item.address, item.symbol.name, item.library_ordinal,
                      item.binding_class, item.binding_type, item.addend, item.weak_import)
                     for item in binary.dyld_info.bindings],
        "rebases": [(item.address, item.size, item.type) for item in binary.relocations],
        "exports": [(item.symbol.name, item.address, item.flags)
                    for item in binary.dyld_info.exports],
    }


def convert_payload(source, destination):
    parsed = lief.MachO.parse(source)
    if parsed is None or len(parsed) != 1:
        raise ValueError("Expected a thin arm64 Runner")
    binary = parsed.at(0)
    if binary.header.cpu_type != lief.MachO.Header.CPU_TYPE.ARM64:
        raise ValueError("Expected an arm64 Runner")
    if binary.available_command_space < 128:
        raise ValueError("Insufficient Mach-O header padding")
    before_state = payload_state(binary)
    payload_name = "@rpath/RunnerPayload.dylib"
    if binary.header.file_type == lief.MachO.Header.FILE_TYPE.EXECUTE:
        binary.header.file_type = lief.MachO.Header.FILE_TYPE.DYLIB
        binary.header.remove(lief.MachO.Header.FLAGS.PIE)
        binary.remove(lief.MachO.LoadCommand.TYPE.MAIN)
        pagezero = binary.get_segment("__PAGEZERO")
        if pagezero is not None:
            binary.remove(pagezero)
        binary.add(lief.MachO.DylibCommand.id_dylib(payload_name))
    elif binary.header.file_type == lief.MachO.Header.FILE_TYPE.DYLIB:
        for library in binary.libraries:
            if library.command == lief.MachO.LoadCommand.TYPE.ID_DYLIB:
                library.name = payload_name
    else:
        raise ValueError("Runner must be an executable or debug dylib")
    parsed.write(destination)
    if payload_state(lief.MachO.parse(destination).at(0)) != before_state:
        raise RuntimeError("Payload conversion changed code or dyld binding semantics")
    return before_state


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("app", type=Path)
    parser.add_argument("--sdk", choices=("iphoneos", "iphonesimulator"), default="iphoneos")
    parser.add_argument("--flutter-framework", type=Path, required=True)
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()
    source = args.app.resolve()
    headers = args.flutter_framework.resolve()
    if not (headers / "Headers/Flutter.h").is_file():
        parser.error("Matching Flutter.framework with Headers is required")
    root = Path(__file__).resolve().parents[2]
    tools = Path(__file__).resolve().parent
    parent = root / "build/ios/startup-probe"
    parent.mkdir(parents=True, exist_ok=True)
    if args.output:
        output = args.output.resolve()
        output.mkdir(parents=True, exist_ok=False)
    else:
        output = Path(tempfile.mkdtemp(prefix=f"launcher-{args.sdk}-", dir=parent))
    # Reuse the same native UI, framework inventory and dependency ordering as Probe.
    run(sys.executable, tools / "build.py", source, "--sdk", args.sdk,
        "--output", output / "probe-base")
    app = output / "Payload/StartupProbe.app"
    app.parent.mkdir()
    shutil.copytree(output / "probe-base/Payload/StartupProbe.app", app)
    with (source / "Info.plist").open("rb") as stream:
        original_info = plistlib.load(stream)
    with (app / "Info.plist").open("rb") as stream:
        info = plistlib.load(stream)
    info["CFBundleIdentifier"] = "moe.alphaly.art3m1s.startuplauncher"
    info["CFBundleDisplayName"] = "Art3m1s Trace"
    for key in ("CADisableMinimumFrameDurationOnPhone", "NSDocumentsFolderUsageDescription",
                "NSLocalNetworkUsageDescription", "NSBonjourServices", "NSAppTransportSecurity"):
        if key in original_info:
            info[key] = original_info[key]
    with (app / "Info.plist").open("wb") as stream:
        plistlib.dump(info, stream)
    # Resource bundles include Flutter's original Main storyboard and plugin assets.
    for resource in source.iterdir():
        if resource.suffix in (".lproj", ".bundle"):
            shutil.copytree(resource, app / resource.name, dirs_exist_ok=True)
    runner = source / original_info["CFBundleExecutable"]
    debug_runner = source / f"{runner.name}.debug.dylib"
    payload_source = debug_runner if debug_runner.is_file() else runner
    source_digest = hashlib.sha256(payload_source.read_bytes()).hexdigest()
    payload = app / "Frameworks/RunnerPayload.dylib"
    before_state = convert_payload(payload_source, payload)

    compiler = ["xcrun", "--sdk", args.sdk, "clang", "-target",
                "arm64-apple-ios13.0" + ("-simulator" if args.sdk == "iphonesimulator" else ""),
                "-isysroot", run("xcrun", "--sdk", args.sdk, "--show-sdk-path")]
    for name in ("main", "trace", "launcher_bridge"):
        run(*compiler, "-fobjc-arc", "-fblocks", "-g", "-O0", "-Wall", "-Wextra",
            "-Wno-unused-parameter", "-DART_LAUNCH_RUNNER=1", "-F", headers.parent,
            "-c", tools / f"{name}.m", "-o", output / f"{name}.o")
    run(*compiler, output / "main.o", "-framework", "UIKit", "-framework", "Foundation",
        "-framework", "CoreGraphics", "-Wl,-rpath,@executable_path/Frameworks",
        "-Wl,-rpath,/usr/lib/swift", "-o", app / "StartupProbe")
    bridge = app / "Frameworks/RunnerBridge.dylib"
    run(*compiler, output / "trace.o", output / "launcher_bridge.o", "-dynamiclib",
        "-F", headers.parent, "-framework", "Flutter", "-framework", "UIKit", "-framework", "Foundation",
        "-Wl,-rpath,@executable_path/Frameworks", "-install_name", "@rpath/RunnerBridge.dylib", "-o", bridge)
    for executable, dsym_name in ((app / "StartupProbe", "StartupProbe.app"), (bridge, "RunnerBridge.dylib")):
        run("xcrun", "dsymutil", executable, "-o", output / f"{dsym_name}.dSYM")
    dsym = source.parent / f"{source.name}.dSYM"
    if dsym.is_dir():
        shutil.copytree(dsym, output / dsym.name)
    manifest_path = app / "ProbeManifest.plist"
    with manifest_path.open("rb") as stream:
        manifest = plistlib.load(stream)
    manifest["steps"].extend([
        {"path": "Frameworks/RunnerPayload.dylib", "weak": False},
        {"path": "Frameworks/RunnerBridge.dylib", "weak": False},
    ])
    with manifest_path.open("wb") as stream:
        plistlib.dump(manifest, stream)
    for item in sorted((app / "Frameworks").iterdir()):
        if item.suffix in (".framework", ".dylib"):
            run("codesign", "--force", "--sign", "-", "--timestamp=none", item)
    run("codesign", "--force", "--sign", "-", "--timestamp=none", app)
    run("codesign", "--verify", "--deep", "--strict", app)
    if payload_state(lief.MachO.parse(payload).at(0)) != before_state:
        raise RuntimeError("Payload signing changed code or dyld binding semantics")
    if hashlib.sha256(payload_source.read_bytes()).hexdigest() != source_digest:
        raise RuntimeError("Source Runner changed during build")
    if binary_uuid(payload) != binary_uuid(payload_source):
        raise RuntimeError("Payload UUID changed")
    ipa = output / "Art3m1s-native-trace.ipa"
    run("ditto", "-c", "-k", "--norsrc", "--noextattr", "--keepParent", app.parent, ipa)
    inventory = {
        "sourceApp": str(source), "sourceRunnerUUID": binary_uuid(runner),
        "sourcePayloadSHA256": source_digest,
        "payloadSHA256": hashlib.sha256(payload.read_bytes()).hexdigest(),
        "payloadUUID": binary_uuid(payload), "payloadSectionsUnchanged": True,
        "payloadBindingSemanticsUnchanged": True, "liefVersion": lief.__version__,
        "launcherUUID": binary_uuid(app / "StartupProbe"), "bridgeUUID": binary_uuid(bridge),
        "ipaSHA256": hashlib.sha256(ipa.read_bytes()).hexdigest(),
        "bundleIdentifier": info["CFBundleIdentifier"], "steps": manifest["steps"],
    }
    (output / "launcher-inventory.json").write_text(json.dumps(inventory, indent=2) + "\n")
    print(f"App: {app}\nIPA: {ipa}\nSHA-256: {inventory['ipaSHA256']}")


if __name__ == "__main__":
    main()
