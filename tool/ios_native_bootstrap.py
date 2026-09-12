"""Generate the native launch dependency order from the app Xcode just assembled."""

import argparse
import json
import plistlib
from pathlib import Path
import re
import shutil
import subprocess


def libraries(binary):
    result = subprocess.check_output(
        ["xcrun", "dyld_info", "-linked_dylibs", str(binary)], text=True
    )
    links = []
    for line in result.split("    -rpaths:", 1)[0].splitlines():
        match = re.fullmatch(r"\s*(weak-link\s+)?([/@]\S+)\s*", line)
        if match:
            links.append((match[2], bool(match[1])))
    return links


def generate(app, products=None, reference=None):
    if reference is None:
        reference = Path(__file__).resolve().parents[1] / "ios/Native/ProbeLoadOrder.json"
    reference_paths = json.loads(reference.read_text())["paths"]
    binaries = {}
    for framework in sorted((app / "Frameworks").glob("*.framework")):
        info = plistlib.loads((framework / "Info.plist").read_bytes())
        binary = framework / info["CFBundleExecutable"]
        binaries[f"@rpath/{framework.name}/{binary.name}"] = binary
    for binary in sorted((app / "Frameworks").glob("*.dylib")):
        binaries[f"@rpath/{binary.name}"] = binary
    runtime = "@rpath/Art3m1sRuntime.dylib"
    if runtime not in binaries:
        raise ValueError("Art3m1sRuntime.dylib was not embedded")
    info = plistlib.loads((app / "Info.plist").read_bytes())
    if info.get("UIApplicationSceneManifest") or info.get("UIMainStoryboardFile"):
        raise ValueError("The native entry must create its legacy window before loading Flutter")
    def is_system(name):
        # Swift packages may record system Swift runtimes through the loader's
        # rpath even though dyld resolves them from /usr/lib/swift.
        return name.startswith(("/System/Library/", "/usr/lib/")) or (
            name.startswith("@rpath/libswift_") and name.endswith(".dylib")
        )

    if any(not is_system(name) for name, _ in libraries(app / info["CFBundleExecutable"])):
        raise ValueError("The native executable must only link system libraries")

    dependencies = {name: libraries(binary) for name, binary in binaries.items()}
    system = {}
    for links in [dependencies[runtime], *dependencies.values()]:
        for name, weak in links:
            if is_system(name):
                system[name] = system.get(name, True) and weak
            elif name not in binaries:
                raise ValueError(f"Missing embedded dependency: {name}")
    system_order = [name for name in reference_paths if name in system]
    system_order += [name for name in system if name not in system_order]
    steps = [{"path": name, "weak": system[name]} for name in system_order]
    visited = set()
    visiting = set()

    def visit(name):
        if name in visited or name in visiting:
            return
        visiting.add(name)
        for dependency, _ in dependencies[name]:
            if dependency in binaries:
                visit(dependency)
        visiting.remove(name)
        visited.add(name)
        steps.append({"path": binaries[name].relative_to(app).as_posix(), "weak": False})

    embedded_by_path = {binary.relative_to(app).as_posix(): name for name, binary in binaries.items()}
    embedded_order = [embedded_by_path[path] for path in reference_paths if path in embedded_by_path]
    embedded_order += [name for name in binaries if name not in embedded_order]
    for name in embedded_order:
        if name != runtime:
            visit(name)
    visit(runtime)
    # Xcode does not embed SPM resources into a dynamic-library product. Its
    # resource accessors search Bundle.main, so put the built bundles in the app.
    if products:
        for bundle in sorted(products.glob("*.bundle")):
            destination = app / bundle.name
            if destination.exists():
                shutil.rmtree(destination)
            shutil.copytree(bundle, destination)
    with (app / "NativeLibraries.plist").open("wb") as stream:
        plistlib.dump({"steps": steps}, stream)
    print(f"Native startup: {len(steps)} libraries, system-only executable")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("app", type=Path)
    parser.add_argument("--products", type=Path)
    args = parser.parse_args()
    generate(args.app.resolve(), args.products)
