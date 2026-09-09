#!/bin/bash
set -euo pipefail

project="GetEmDone.xcodeproj"
derived_data="${1:-.DerivedDataExtensionValidation}"

required_targets=(
  GetEmDone
  GetEmDoneCore
  GetEmDoneDeviceActivityMonitor
  GetEmDoneShieldConfiguration
  GetEmDoneShieldAction
  GetEmDoneTests
)

project_listing="$(xcodebuild -project "$project" -list)"
for target in "${required_targets[@]}"; do
  if ! grep -Fq "        $target" <<< "$project_listing"; then
    echo "Missing required Xcode target: $target" >&2
    exit 1
  fi
done

for extension_target in \
  GetEmDoneDeviceActivityMonitor \
  GetEmDoneShieldConfiguration \
  GetEmDoneShieldAction; do
  xcodebuild \
    -project "$project" \
    -target "$extension_target" \
    -configuration Debug \
    -sdk iphonesimulator \
    SYMROOT="$derived_data/Build/Products" \
    OBJROOT="$derived_data/Build/Intermediates.noindex" \
    SHARED_PRECOMPS_DIR="$derived_data/Build/Intermediates.noindex/PrecompiledHeaders" \
    CLANG_MODULE_CACHE_PATH="$derived_data/ModuleCache.noindex" \
    SWIFT_MODULE_CACHE_PATH="$derived_data/ModuleCache.noindex" \
    CODE_SIGNING_ALLOWED=NO \
    build
done

for plist in Extensions/*/Info.plist; do
  plutil -lint "$plist"
done

for entitlements in Configuration/Entitlements/*.entitlements; do
  plutil -lint "$entitlements"
  /usr/libexec/PlistBuddy -c 'Print :com.apple.developer.family-controls' "$entitlements" | grep -Fxq true
  /usr/libexec/PlistBuddy -c 'Print :com.apple.security.application-groups:0' "$entitlements" | grep -Fxq group.com.getemdone.shared
done
