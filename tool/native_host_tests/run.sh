#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/../.."
test_dir=$(mktemp -d "${TMPDIR:-/tmp}/art3m1s-native-tests.XXXXXX")
trap 'rm -rf "$test_dir"' EXIT
sources=native/ios/Art3m1sNative/Art3m1sNative
xcrun swiftc -parse-as-library -module-cache-path "$test_dir/Modules" \
  "$sources/Models/GameModels.swift" \
  "$sources/Services/InputGate.swift" \
  "$sources/Services/AppDataPaths.swift" \
  "$sources/Services/AppLogger.swift" \
  "$sources/Services/GameImporter.swift" \
  "$sources/Services/GameManifest.swift" \
  "$sources/Services/LibraryStore.swift" \
  "$sources/Services/ProjectVFS.swift" \
  "$sources/Services/ScriptHTTPClient.swift" \
  "$sources/Services/NativeTranslationService.swift" \
  tool/native_host_tests/HostTests.swift -o "$test_dir/host-tests"
"$test_dir/host-tests"
