#!/usr/bin/env python3
"""Export art3m1s-core Cargo.lock licenses for the Flutter about page."""

from __future__ import annotations

import argparse
import json
import os
import re
from pathlib import Path

LICENSE_EXACT = {
    "LICENSE",
    "LICENSE.md",
    "LICENSE.txt",
    "LICENCE",
    "LICENCE.md",
    "COPYING",
    "COPYING.md",
    "LICENSE-MIT",
    "LICENSE-APACHE",
    "LICENSE-MPL",
    "LICENSE-MPL-2.0",
    "LICENSE-BSD",
    "UNLICENSE",
}

WORKSPACE = {
    "art3m1s-core": Path("."),
    "art3m1s-emote": Path("crates/art3m1s-emote"),
    "asb-interpreter": Path("crates/asb-interpreter"),
    "eluna_rs": Path("crates/eluna"),
    "pf8": Path("crates/pf8"),
    "pfs-upk-rust": Path("crates/pfs-upk-rust"),
}


def read_text(path: Path) -> str:
    data = path.read_bytes()
    for encoding in ("utf-8", "utf-8-sig", "latin-1"):
        try:
            return data.decode(encoding)
        except UnicodeDecodeError:
            continue
    return data.decode("utf-8", errors="replace")


def parse_lock(lock_text: str) -> list[tuple[str, str, str | None]]:
    packages: list[tuple[str, str, str | None]] = []
    for block in lock_text.split("[[package]]")[1:]:
        name = re.search(r'^name = "([^"]+)"', block, re.M)
        version = re.search(r'^version = "([^"]+)"', block, re.M)
        source = re.search(r'^source = "([^"]+)"', block, re.M)
        if name and version:
            packages.append(
                (name.group(1), version.group(1), source.group(1) if source else None)
            )
    return packages


def git_rev_from_source(source: str) -> str | None:
    if "#" not in source:
        return None
    rev = source.rsplit("#", 1)[1].strip()
    return rev or None


def git_rev_matches(dir_name: str, rev_hash: str) -> bool:
    return rev_hash.startswith(dir_name) or dir_name.startswith(rev_hash)


def cargo_identity_matches(toml_text: str, name: str, version: str) -> bool:
    return (
        f'name = "{name}"' in toml_text and f'version = "{version}"' in toml_text
    )


def find_dir(core: Path, name: str, version: str, source: str | None) -> Path | None:
    if source is None:
        relative = WORKSPACE.get(name)
        return (core / relative) if relative else None
    if source.startswith("registry+"):
        registry = Path.home() / ".cargo/registry/src/index.crates.io-1949cf8c6b5b557f"
        candidate = registry / f"{name}-{version}"
        return candidate if candidate.is_dir() else None
    if source.startswith("git+"):
        git_root = Path.home() / ".cargo/git/checkouts"
        if not git_root.is_dir():
            return None
        rev_hash = git_rev_from_source(source)
        matches: list[Path] = []
        hash_matches: list[Path] = []
        for repo in git_root.iterdir():
            if not repo.is_dir():
                continue
            for rev in repo.iterdir():
                if not rev.is_dir():
                    continue
                toml = rev / "Cargo.toml"
                if not toml.exists():
                    continue
                text = toml.read_text(errors="ignore")
                if not cargo_identity_matches(text, name, version):
                    continue
                matches.append(rev)
                if rev_hash and git_rev_matches(rev.name, rev_hash):
                    hash_matches.append(rev)
        if hash_matches:
            return hash_matches[0]
        return matches[0] if matches else None
    return None


def spdx_of(directory: Path) -> str:
    toml = directory / "Cargo.toml"
    if not toml.exists():
        return ""
    text = toml.read_text(errors="ignore")
    match = re.search(r'^license\s*=\s*"([^"]+)"', text, re.M)
    if match:
        return match.group(1)
    match = re.search(r"^license\s*=\s*'([^']+)'", text, re.M)
    return match.group(1) if match else ""


def infer_spdx(text: str) -> str:
    upper = text.upper()
    if "MOZILLA PUBLIC LICENSE" in upper and "2.0" in text:
        return "MPL-2.0"
    if "GNU AFFERO GENERAL PUBLIC LICENSE" in upper:
        return "AGPL-3.0-only"
    if (
        "REDISTRIBUTION AND USE IN SOURCE AND BINARY FORMS" in upper
        and "NEITHER THE NAME" in upper
    ):
        return "BSD-3-Clause"
    if "APACHE LICENSE" in upper and "VERSION 2.0" in upper:
        return "Apache-2.0"
    if "PERMISSION IS HEREBY GRANTED, FREE OF CHARGE" in upper:
        return "MIT"
    return ""


def looks_like_agpl(text: str) -> bool:
    return "GNU AFFERO GENERAL PUBLIC LICENSE" in text.upper()


def license_files(directory: Path) -> list[Path]:
    files: list[Path] = []
    for path in sorted(directory.iterdir()):
        if not path.is_file():
            continue
        name = path.name.upper()
        if name in LICENSE_EXACT or name.startswith("LICENSE"):
            files.append(path)
    return files


def export(core: Path) -> list[dict[str, str]]:
    packages = parse_lock((core / "Cargo.lock").read_text())
    root_mpl = read_text(core / "LICENSE").strip()
    exported: list[dict[str, str]] = []
    missing: list[str] = []
    for name, version, source in packages:
        directory = find_dir(core, name, version, source)
        if directory is None:
            missing.append(f"{name} {version}")
            continue
        declared = spdx_of(directory)
        files = license_files(directory)
        chunks: list[str] = []
        for path in files:
            body = read_text(path).strip()
            if not body:
                continue
            chunks.append(f"--- {path.name} ---\n{body}" if len(files) > 1 else body)
        text = "\n\n".join(chunks).strip()
        if name in WORKSPACE and declared == "MPL-2.0" and looks_like_agpl(text):
            text = root_mpl
        if not text:
            if declared == "MPL-2.0" and name in WORKSPACE:
                text = root_mpl
            elif declared:
                text = (
                    f"SPDX-License-Identifier: {declared}\n\n"
                    "This crate did not ship a standalone license file."
                )
            else:
                text = "License text was not bundled with this crate."
        spdx = declared or infer_spdx(text)
        exported.append(
            {
                "package": name,
                "version": version,
                "spdx": spdx,
                "text": text,
            }
        )
    if missing:
        raise SystemExit("missing crate sources:\n" + "\n".join(missing))
    return exported


def default_core() -> Path:
    env = os.environ.get("ART3M1S_CORE")
    if env:
        return Path(env).expanduser()
    here = Path(__file__).resolve()
    candidates = [
        here.parents[1] / "art3m1s-core",
        Path("/Users/alphaly/RustroverProjects/art3m1s-core"),
    ]
    for candidate in candidates:
        if (candidate / "Cargo.lock").exists():
            return candidate
    raise SystemExit("art3m1s-core not found; set ART3M1S_CORE")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--core", type=Path, default=None)
    parser.add_argument(
        "--output",
        type=Path,
        default=Path(__file__).resolve().parents[1]
        / "assets/licenses/rust_third_party.json",
    )
    args = parser.parse_args()
    core = args.core or default_core()
    payload = export(core)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(
        json.dumps(payload, ensure_ascii=False, separators=(",", ":")),
        encoding="utf-8",
    )
    print(f"wrote {len(payload)} licenses to {args.output}")


if __name__ == "__main__":
    main()
