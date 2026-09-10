"""Build an isolated library-loading probe from an existing Runner.app."""

import argparse
import hashlib
import json
from pathlib import Path
import plistlib
import re
import shutil
import subprocess
import tempfile


def run(*args):
    return subprocess.check_output([str(arg) for arg in args], text=True).strip()


def linked_libraries(binary):
    output = run("xcrun", "dyld_info", "-linked_dylibs", binary)
    result = []
    for line in output.split("    -rpaths:", 1)[0].splitlines():
        match = re.fullmatch(r"\s*(weak-link\s+)?([/@]\S+)\s*", line)
        if match:
            result.append((match[2], bool(match[1])))
    return result


def binary_uuid(binary):
    return run("xcrun", "dwarfdump", "--uuid", binary).splitlines()[0].split()[1]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("app", type=Path)
    parser.add_argument("--sdk", choices=("iphoneos", "iphonesimulator"), default="iphoneos")
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()
    source = args.app.resolve()
    with (source / "Info.plist").open("rb") as stream:
        source_info = plistlib.load(stream)
    expected_platform = "iPhoneOS" if args.sdk == "iphoneos" else "iPhoneSimulator"
    if expected_platform not in source_info["CFBundleSupportedPlatforms"]:
        parser.error(f"Source app is not built for {expected_platform}")
    root = Path(__file__).resolve().parents[2]
    parent = root / "build/ios/startup-probe"
    parent.mkdir(parents=True, exist_ok=True)
    if args.output:
        output = args.output.resolve()
        output.mkdir(parents=True, exist_ok=False)
    else:
        output = Path(tempfile.mkdtemp(prefix=f"{args.sdk}-", dir=parent))
    app = output / "Payload/StartupProbe.app"
    app.mkdir(parents=True)
    shutil.copytree(source / "Frameworks", app / "Frameworks")

    runner = source / source_info["CFBundleExecutable"]
    # Xcode debug builds put application linkage in a separate dylib.
    debug_dylib = source / f"{runner.name}.debug.dylib"
    link_root = debug_dylib if debug_dylib.is_file() else runner
    binaries = {}
    for framework in sorted((source / "Frameworks").glob("*.framework")):
        with (framework / "Info.plist").open("rb") as stream:
            executable = plistlib.load(stream)["CFBundleExecutable"]
        binaries[f"@rpath/{framework.name}/{executable}"] = framework / executable
    if list((source / "Frameworks").glob("*.dylib")):
        for dylib in sorted((source / "Frameworks").glob("*.dylib")):
            binaries[f"@rpath/{dylib.name}"] = dylib
    dependencies = {name: linked_libraries(binary) for name, binary in binaries.items()}
    system = {}
    for links in [linked_libraries(link_root), *dependencies.values()]:
        for name, weak in links:
            if name.startswith("/"):
                system[name] = system.get(name, True) and weak
            elif name not in binaries:
                raise ValueError(f"Unresolved embedded dependency: {name}")

    steps = [{"path": name, "weak": weak} for name, weak in system.items()]
    visited = set()

    def visit(name):
        if name in visited:
            return
        visited.add(name)
        for dependency, _ in dependencies[name]:
            if dependency in binaries:
                visit(dependency)
        relative = binaries[name].relative_to(source).as_posix()
        steps.append({"path": relative, "weak": False})

    # All system dependencies are made visible before libraries that use
    # -undefined dynamic_lookup (notably mpv and objective_c).
    for name in binaries:
        visit(name)
    manifest = {"sourceRunnerUUID": binary_uuid(runner), "steps": steps}
    with (app / "ProbeManifest.plist").open("wb") as stream:
        plistlib.dump(manifest, stream)
    inventory = {}
    source_binaries = {"Runner": runner, **binaries}
    if link_root != runner:
        source_binaries[link_root.name] = link_root
    for name, binary in source_binaries.items():
        inventory[name] = {
            "uuid": binary_uuid(binary),
            "sha256BeforeProbeSigning": hashlib.sha256(binary.read_bytes()).hexdigest(),
        }
    (output / "source-inventory.json").write_text(json.dumps({
        "sourceApp": str(source), "binaries": inventory, "steps": steps,
    }, indent=2) + "\n")

    info = {
        "CFBundleIdentifier": "moe.alphaly.art3m1s.startupprobe",
        "CFBundleDisplayName": "Art3m1s Probe",
        "CFBundleDevelopmentRegion": "en",
        "CFBundleName": "StartupProbe",
        "CFBundleExecutable": "StartupProbe",
        "CFBundlePackageType": "APPL",
        "CFBundleShortVersionString": "1.0",
        "CFBundleVersion": "1",
        "CFBundleSupportedPlatforms": [expected_platform],
        "MinimumOSVersion": "13.0",
        "LSRequiresIPhoneOS": True,
        "UIDeviceFamily": [1, 2],
        "UIFileSharingEnabled": True,
        "LSSupportsOpeningDocumentsInPlace": True,
        "UILaunchScreen": {},
        "UISupportedInterfaceOrientations": ["UIInterfaceOrientationPortrait"],
    }
    for key in ("CFBundleIcons", "CFBundleIcons~ipad"):
        if key in source_info:
            info[key] = source_info[key]
    for asset in [source / "Assets.car", *source.glob("AppIcon*.png")]:
        if asset.is_file():
            shutil.copy2(asset, app / asset.name)
    with (app / "Info.plist").open("wb") as stream:
        plistlib.dump(info, stream)

    target = "arm64-apple-ios13.0" + ("-simulator" if args.sdk == "iphonesimulator" else "")
    compiler = ["xcrun", "--sdk", args.sdk, "clang", "-target", target,
                "-isysroot", run("xcrun", "--sdk", args.sdk, "--show-sdk-path")]
    object_file = output / "main.o"
    run(*compiler,
        "-fobjc-arc", "-g", "-O0", "-Wall", "-Wextra", "-Wno-unused-parameter",
        "-c", Path(__file__).with_name("main.m"), "-o", object_file)
    run(*compiler, object_file,
        "-framework", "UIKit", "-framework", "Foundation", "-framework", "CoreGraphics",
        "-Wl,-rpath,@executable_path/Frameworks",
        "-o", app / "StartupProbe")
    run("xcrun", "dsymutil", app / "StartupProbe", "-o", output / "StartupProbe.app.dSYM")
    for binary in sorted((app / "Frameworks").iterdir()):
        if binary.suffix in (".framework", ".dylib"):
            run("codesign", "--force", "--sign", "-", "--timestamp=none", binary)
    run("codesign", "--force", "--sign", "-", "--timestamp=none", app)
    run("codesign", "--verify", "--deep", "--strict", app)
    ipa = output / "Art3m1s-startup-probe.ipa"
    run("ditto", "-c", "-k", "--norsrc", "--noextattr", "--keepParent", app.parent, ipa)
    print(f"App: {app}\nIPA: {ipa}\nSource UUID: {manifest['sourceRunnerUUID']}\nSteps: {len(steps)}")


if __name__ == "__main__":
    main()
