#!/usr/bin/env bash
set -euo pipefail

source_root="${SRCROOT}/../.build/krkr-macos"
host_source="${source_root}/libart3m1s_krkr_host.dylib"
resources_source="${source_root}/Res"
if [[ -z "${TARGET_BUILD_DIR:-}" || -z "${EXECUTABLE_FOLDER_PATH:-}" ]]; then
  echo "error: Xcode did not provide the KRKR bundle destination" >&2
  exit 1
fi
executable_dest="${TARGET_BUILD_DIR}/${EXECUTABLE_FOLDER_PATH}"
resources_dest="${TARGET_BUILD_DIR}/${UNLOCALIZED_RESOURCES_FOLDER_PATH}/krkr"

# Always clear outputs from a previous opt-in build. This prevents a normal
# build from accidentally shipping stale KRKR code or resources.
/bin/rm -f "${executable_dest}/libart3m1s_krkr_host.dylib"
/bin/rm -rf "${executable_dest}/Res" "${resources_dest}"

# ART3M1S_ENABLE_KRKR is opt-in. A normal macOS build has no staged runtime
# and keeps the existing Artemis/RFVP bundle unchanged.
if [[ ! -f "${host_source}" ]]; then
  exit 0
fi
if [[ ! -d "${resources_source}" ]]; then
  echo "error: KRKR runtime is staged without its Res directory" >&2
  exit 1
fi

mkdir -p "${executable_dest}" "${resources_dest}"
/bin/cp -f "${host_source}" "${executable_dest}/libart3m1s_krkr_host.dylib"
/usr/bin/ditto "${resources_source}" "${resources_dest}/Res"

sign_identity="${EXPANDED_CODE_SIGN_IDENTITY:-}"
if [[ -z "${sign_identity}" ]]; then
  sign_identity="-"
fi
/usr/bin/codesign --force --sign "${sign_identity}" --timestamp=none \
  "${executable_dest}/libart3m1s_krkr_host.dylib"
