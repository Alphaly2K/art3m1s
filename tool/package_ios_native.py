"""Ad-hoc sign a staged copy of one native-entry app and package its IPA/dSYMs."""

import argparse
import hashlib
import json
from pathlib import Path
import plistlib
import shutil
import subprocess
import tempfile

from ios_native_bootstrap import libraries


def run(*args):
    return subprocess.check_output([str(arg) for arg in args], text=True).strip()


def uuids(binary):
    return [line.split()[1] for line in run("xcrun", "dwarfdump", "--uuid", binary).splitlines()]


def package(source, output):
    source, output = source.resolve(), output.resolve()
    info = plistlib.loads((source / "Info.plist").read_bytes())
    if info.get("UIApplicationSceneManifest") or info.get("UIMainStoryboardFile"):
        raise ValueError("Expected the native legacy-window entry")
    if "iPhoneOS" not in info.get("CFBundleSupportedPlatforms", []):
        raise ValueError("An IPA must contain a device build")
    manifest = plistlib.loads((source / "NativeLibraries.plist").read_bytes())
    if any(not path.startswith(("/System/Library/", "/usr/lib/")) for path, _ in libraries(source / info["CFBundleExecutable"])):
        raise ValueError("Runner must only link system libraries")
    output.parent.mkdir(parents=True, exist_ok=True)
    symbols = output.with_suffix(".dSYMs")
    symbols.mkdir(exist_ok=True)
    symbol_inventory = {}
    for binary, dsym in (
        (source / info["CFBundleExecutable"], source.parent / "Runner.app.dSYM"),
        (source / "Frameworks/Art3m1sRuntime.dylib", source.parent / "Art3m1sRuntime.dylib.dSYM"),
        (source / "Frameworks/App.framework/App", source.parent / "App.framework.dSYM"),
    ):
        if not dsym.is_dir() or uuids(binary) != uuids(dsym):
            raise ValueError(f"Missing or mismatched dSYM for {binary}")
        shutil.copytree(dsym, symbols / dsym.name, dirs_exist_ok=True)
        symbol_inventory[binary.name] = uuids(binary)
    with tempfile.TemporaryDirectory(prefix="native-ipa-", dir=output.parent) as temporary:
        payload = Path(temporary) / "Payload"
        app = payload / "Runner.app"
        shutil.copytree(source, app, symlinks=True)
        # Match the successful Trace's ad-hoc signing without platform/Unsandbox entitlements.
        for binary in sorted((app / "Frameworks").iterdir()):
            if binary.suffix in (".framework", ".dylib"):
                run("codesign", "--force", "--sign", "-", "--timestamp=none", binary)
        run("codesign", "--force", "--sign", "-", "--timestamp=none", app)
        run("codesign", "--verify", "--deep", "--strict", app)
        run("ditto", "-c", "-k", "--norsrc", "--noextattr", "--keepParent", payload, output)
    report = {
        "sourceApp": str(source), "bundleIdentifier": info["CFBundleIdentifier"],
        "ipaSHA256": hashlib.sha256(output.read_bytes()).hexdigest(),
        "uuids": symbol_inventory, "steps": manifest["steps"],
    }
    output.with_suffix(".json").write_text(json.dumps(report, indent=2) + "\n")
    print(f"IPA: {output}\ndSYMs: {symbols}\nSHA-256: {report['ipaSHA256']}")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("app", type=Path)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    package(args.app, args.output)
