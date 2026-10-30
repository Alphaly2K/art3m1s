#!/usr/bin/env python3
"""Export resolved Cargo dependency licenses for the application about pages."""

from __future__ import annotations

import argparse
import json
import os
import re
import subprocess
from pathlib import Path

STANDARD_TEXTS = Path(__file__).resolve().parent / "license_texts"


def read_text(path: Path) -> str:
    return path.read_bytes().decode("utf-8-sig", errors="replace").strip()


def license_files(directory: Path) -> list[Path]:
    return sorted(
        p for p in directory.iterdir()
        if p.is_file() and p.name.upper().startswith(("LICENSE", "LICENCE", "COPYING", "UNLICENSE"))
    )


def infer_spdx(text: str) -> str:
    upper = text.upper()
    if "MOZILLA PUBLIC LICENSE" in upper and "2.0" in text:
        return "MPL-2.0"
    if "GNU LESSER GENERAL PUBLIC LICENSE" in upper and "Version 2.1" in text:
        return "LGPL-2.1-or-later"
    if "GNU AFFERO GENERAL PUBLIC LICENSE" in upper:
        return "AGPL-3.0-only"
    if "APACHE LICENSE" in upper and "VERSION 2.0" in upper:
        return "Apache-2.0"
    if "PERMISSION IS HEREBY GRANTED, FREE OF CHARGE" in upper:
        return "MIT"
    if "REDISTRIBUTION AND USE IN SOURCE AND BINARY FORMS" in upper:
        return "BSD-3-Clause" if "NEITHER THE NAME" in upper else "BSD-2-Clause"
    return ""


def inherited_license(directory: Path, declared: str) -> list[Path]:
    # Path dependencies may inherit their repository's license, including
    # workspace members whose manifest has no separate declaration.
    for ancestor in directory.parents:
        files = license_files(ancestor)
        matching = [p for p in files if not declared or infer_spdx(read_text(p)) == declared]
        if matching:
            return matching
        if (ancestor / ".git").exists():
            break
    return []


def export(metadata: dict) -> list[dict[str, str]]:
    exported: list[dict[str, str]] = []
    missing: list[str] = []
    for package in sorted(metadata["packages"], key=lambda p: (p["name"], p["version"])):
        directory = Path(package["manifest_path"]).parent
        declared = package.get("license") or ""
        files = license_files(directory)
        if package.get("license_file"):
            explicit = directory / package["license_file"]
            if explicit not in files:
                files.append(explicit)
        local = package.get("source") is None
        if not files and local:
            files = inherited_license(directory, declared)
        chunks = [f"--- {p.name} ---\n{read_text(p)}" for p in files if read_text(p)]
        spdx = declared or (infer_spdx("\n".join(chunks)) if chunks else "")
        if not chunks and spdx:
            # Select Apache for dual-licensed crates lacking bundled texts.
            selected = "Apache-2.0" if "Apache-2.0" in spdx else spdx
            standard = STANDARD_TEXTS / f"{selected}.txt"
            if standard.exists():
                chunks.append(f"License choice: {selected}\n\n{read_text(standard)}")
            else:
                chunks.append(f"SPDX-License-Identifier: {spdx}")
        if local:
            exceptions: dict[str, list[str]] = {}
            for source in sorted((directory / "src").rglob("*.rs")):
                identifiers = re.findall(r"SPDX-License-Identifier:\s*([^\r\n]+)", read_text(source))
                for identifier in identifiers:
                    identifier = identifier.strip()
                    if identifier != spdx:
                        exceptions.setdefault(identifier, []).append(str(source.relative_to(directory)))
            for identifier, sources in exceptions.items():
                text = STANDARD_TEXTS / f"{identifier}.txt"
                if not text.exists():
                    raise SystemExit(f"missing license text for {package['name']}: {identifier}")
                chunks.append(f"Files: {', '.join(sources)}\nSPDX-License-Identifier: {identifier}\n\n{read_text(text)}")
                spdx = f"{spdx} AND {identifier}" if spdx else identifier
        if not spdx or not chunks:
            missing.append(f"{package['name']} {package['version']}")
            continue
        exported.append({
            "package": package["name"], "version": package["version"],
            "spdx": spdx, "text": "\n\n".join(chunks),
        })
    if missing:
        raise SystemExit("missing license declarations:\n" + "\n".join(missing))
    return exported


def default_core() -> Path:
    configured = os.environ.get("ART3M1S_CORE") or os.environ.get("CORE_SRC")
    return Path(configured).expanduser() if configured else Path(__file__).resolve().parents[2] / "art3m1s-core"


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--core", type=Path, default=None)
    parser.add_argument("--metadata", type=Path, help="Reuse cargo metadata --all-features --locked output")
    parser.add_argument("--output", type=Path, default=Path(__file__).resolve().parents[1] / "assets/licenses/rust_third_party.json")
    args = parser.parse_args()
    if args.metadata:
        metadata = json.loads(args.metadata.read_text())
    else:
        core = (args.core or default_core()).resolve()
        result = subprocess.run([
            "cargo", "metadata", "--manifest-path", str(core / "Cargo.toml"),
            "--all-features", "--locked", "--format-version", "1",
        ], cwd=core, check=True, stdout=subprocess.PIPE, text=True)
        metadata = json.loads(result.stdout)
    payload = export(metadata)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(payload, ensure_ascii=False, separators=(",", ":")), encoding="utf-8")
    print(f"wrote {len(payload)} licenses to {args.output}")


if __name__ == "__main__":
    main()
