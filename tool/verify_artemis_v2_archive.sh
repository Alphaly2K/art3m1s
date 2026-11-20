#!/usr/bin/env bash
set -euo pipefail

if [[ $# != 2 ]]; then
  printf '%s\n' 'Usage: verify_artemis_v2_archive.sh PREVIEW_ZIP CORE_SRC' >&2
  exit 2
fi

tool_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
scratch=$(mktemp -d)
trap 'rm -rf -- "$scratch"' EXIT

/usr/bin/ditto -x -k "$1" "$scratch"
app="$scratch/art3m1s.app"
mac="$app/Contents/MacOS"
if [[ ! -f "$mac/art3m1s" || ! -x "$mac/art3m1s" ]]; then
  printf '%s\n' 'Artemis v2 archive: missing executable app launcher' >&2
  exit 1
fi
bash "$tool_dir/verify_artemis_v2_macos.sh" "$app"

/usr/bin/xcrun clang -std=c11 -Wall -Wextra -Werror -pedantic -I"$2/doc/abi" \
  "$2/tools/host-smoke/artemis_v2.c" -L"$mac" -lart3m1s_artemis_core \
  -Wl,-rpath,"$mac" -o "$scratch/artemis-v2-smoke"
"$scratch/artemis-v2-smoke"
