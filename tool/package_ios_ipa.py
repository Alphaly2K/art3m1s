"""Ad-hoc sign an iOS app bundle and package it as an IPA."""

import argparse
import hashlib
import plistlib
import shutil
import subprocess
import tempfile
from pathlib import Path


def run(*args):
    subprocess.run([str(arg) for arg in args], check=True)


def package(source: Path, output: Path) -> None:
    source = source.resolve()
    output = output.resolve()
    info = plistlib.loads((source / "Info.plist").read_bytes())
    if "iPhoneOS" not in info.get("CFBundleSupportedPlatforms", []):
        raise ValueError("An IPA must contain a device build")
    output.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="ios-ipa-", dir=output.parent) as temporary:
        payload = Path(temporary) / "Payload"
        app = payload / source.name
        shutil.copytree(source, app, symlinks=True)
        frameworks = app / "Frameworks"
        if frameworks.is_dir():
            for item in sorted(frameworks.iterdir()):
                if item.suffix in (".framework", ".dylib"):
                    run("codesign", "--force", "--sign", "-", "--timestamp=none", item)
        run("codesign", "--force", "--sign", "-", "--timestamp=none", app)
        run("codesign", "--verify", "--deep", "--strict", app)
        run(
            "ditto",
            "-c",
            "-k",
            "--norsrc",
            "--noextattr",
            "--keepParent",
            payload,
            output,
        )
    digest = hashlib.sha256(output.read_bytes()).hexdigest()
    print(f"IPA: {output}\nSHA-256: {digest}")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("app", type=Path)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    package(args.app, args.output)
