#!/usr/bin/env bash
set -euo pipefail

if [[ $# != 1 ]]; then
  printf '%s\n' 'Usage: verify_artemis_v2_macos.sh APP_BUNDLE' >&2
  exit 2
fi

app=$1
mac="$app/Contents/MacOS"
frameworks="$app/Contents/Frameworks"
resources="$app/Contents/Resources"
arch=$(uname -m)

fail() {
  printf 'Artemis v2 bundle: %s\n' "$*" >&2
  exit 1
}

verify_binary() {
  local binary=$1 loads dep path
  [[ -f "$binary" ]] || fail "missing ${binary##*/}"
  loads=$(/usr/bin/otool -arch "$arch" -L "$binary")
  while IFS= read -r dep; do
    case "$dep" in
      /usr/lib/*|/System/Library/*) continue ;;
      @loader_path/*) path="${binary%/*}/${dep#@loader_path/}" ;;
      @executable_path/*) path="$mac/${dep#@executable_path/}" ;;
      @rpath/*)
        path="$frameworks/${dep#@rpath/}"
        if [[ ! -f "$path" ]]; then path="$mac/${dep#@rpath/}"; fi
        ;;
      *) fail "${binary##*/} references external library $dep" ;;
    esac
    [[ -f "$path" ]] || fail "${binary##*/} cannot find $dep in the bundle"
  done < <(printf '%s\n' "$loads" | awk '/^[[:space:]]/ { sub(/^[[:space:]]+/, ""); sub(/ \(compatibility version.*$/, ""); print }')
}

verify_exports() {
  local binary=$1 available symbol
  shift
  available=$(/usr/bin/nm -arch "$arch" -gUj "$binary")
  for symbol in "$@"; do
    [[ $'\n'"$available"$'\n' == *$'\n_'"$symbol"$'\n'* ]] ||
      fail "${binary##*/} is missing export $symbol"
  done
}

for name in libart3m1s_artemis_core.dylib libart3m1s_artemis_metal_host.dylib \
    libart3m1s_artemis_media_host.dylib libEGL.dylib libGLESv2.dylib; do
  verify_binary "$mac/$name"
done
for name in libavcodec.62.dylib libavformat.62.dylib libavutil.60.dylib \
    libswresample.6.dylib libswscale.9.dylib; do
  verify_binary "$frameworks/$name"
done

exports=$(/usr/bin/nm -arch "$arch" -gUj "$mac/libart3m1s_artemis_core.dylib")
[[ "$exports" == _art3m1s_get_api_v2 ]] || fail 'expected only art3m1s_get_api_v2 from Core'
verify_exports "$mac/libart3m1s_artemis_media_host.dylib" art3m1s_artemis_media_get_api_v1

metal_host="$mac/libart3m1s_artemis_metal_host.dylib"
/usr/bin/otool -arch "$arch" -l "$metal_host" | awk '
  $1 == "cmd" { command = $2 }
  $1 == "name" && $2 == "/System/Library/Frameworks/MetalFX.framework/Versions/A/MetalFX" {
    found = (command == "LC_LOAD_WEAK_DYLIB")
  }
  END { exit !found }
' || fail 'Metal Host must weak-link MetalFX'

metal_exports=(
  art3m1s_metal_host_v1_create art3m1s_metal_host_v1_destroy
  art3m1s_metal_host_v1_set_surface art3m1s_metal_host_v1_present art3m1s_metal_host_v1_capture
  art3m1s_metal_host_v1_create_angle art3m1s_metal_host_v1_prepare_glsl art3m1s_metal_host_v1_set_glsl_cache
  art3m1s_metal_host_v1_create_mixed
  art3m1s_metal_host_v1_supports_spatial_upscaling art3m1s_metal_host_v1_set_spatial_upscale
)
compiler_present=
if [[ -n ${ARTEMIS_V2_HLSL_COMPILER_DIR:-} || -e "$mac/artemis-hlsl-compile" ||
    -e "$resources/ArtemisHLSL" ]]; then
  compiler_present=1
fi

dxvk_bridge=libart3m1s_artemis_dxvk_host.dylib
if [[ -n ${ARTEMIS_V2_DXVK_RUNTIME_DIR:-} || -e "$frameworks/$dxvk_bridge" ||
    -e "$resources/ArtemisDXVK-Licenses" || -n $compiler_present ]]; then
  for name in "$dxvk_bridge" libdxvk_d3d11.0.dylib \
      libdxvk_dxgi.0.dylib libMoltenVK.dylib libSDL3.0.dylib; do
    verify_binary "$frameworks/$name"
  done
  for name in DXVK.txt MoltenVK.txt SDL3.txt dxbc-spirv.txt libdisplay-info.txt; do
    [[ -s "$resources/ArtemisDXVK-Licenses/$name" ]] || fail "missing DXVK dependency notice $name"
  done
  verify_exports "$frameworks/$dxvk_bridge" \
    art_dxvk_context_create art_dxvk_context_destroy art_dxvk_context_metal_device \
    art_dxvk_program_create art_dxvk_program_destroy \
    art_dxvk_targets_create art_dxvk_targets_destroy art_dxvk_draw
  metal_exports+=(
    art3m1s_metal_host_v1_create_dxvk art3m1s_metal_host_v1_prepare_ade2
  )
fi
verify_exports "$metal_host" "${metal_exports[@]}"

if [[ -n $compiler_present ]]; then
  for name in artemis-hlsl-compile libvkd3d-utils.1.dylib libvkd3d-shader.1.dylib libvkd3d.1.dylib; do
    verify_binary "$mac/$name"
  done
  [[ -x "$mac/artemis-hlsl-compile" ]] || fail 'HLSL compiler is not executable'
  [[ -s "$resources/ArtemisHLSL/licenses/vkd3d-COPYING.txt" ]] || fail 'missing HLSL compiler license'
  source_files=("$resources"/ArtemisHLSL/source/vkd3d-*.tar.xz)
  [[ -s "${source_files[0]}" ]] || fail 'missing HLSL compiler source archive'
fi

/usr/bin/codesign --verify --deep --strict "$app"
printf '%s\n' 'Verified macOS Artemis v2 bundle.'
