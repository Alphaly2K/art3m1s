#!/bin/sh
set -eu

frameworks="$TARGET_BUILD_DIR/$FRAMEWORKS_FOLDER_PATH"
licenses="$TARGET_BUILD_DIR/$UNLOCALIZED_RESOURCES_FOLDER_PATH/ArtemisDXVK-Licenses"
source=${ARTEMIS_V2_DXVK_RUNTIME_DIR:-}

if [ -z "${ARTEMIS_V2_RUNTIME_DIR:-}" ]; then
  source=
fi

for name in libart3m1s_artemis_dxvk_host.dylib libdxvk_d3d11.0.dylib \
    libdxvk_dxgi.0.dylib libMoltenVK.dylib libSDL3.0.dylib; do
  if [ -z "$source" ]; then
    rm -f "$frameworks/$name"
  else
    mkdir -p "$frameworks"
    cp -f "$source/$name" "$frameworks/$name"
    /usr/bin/codesign --force --sign "${EXPANDED_CODE_SIGN_IDENTITY:--}" --timestamp=none "$frameworks/$name"
  fi
done

rm -rf "$licenses"
if [ -n "$source" ]; then
  /usr/bin/ditto "$source/licenses" "$licenses"
fi
