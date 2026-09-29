#!/usr/bin/env bash

set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "usage: verify-release-bundle.sh <HAHealthSync.app>" >&2
  exit 2
fi

release_app="$1"
release_plist="$release_app/Info.plist"

if [[ ! -d "$release_app" || ! -f "$release_plist" ]]; then
  echo "release app or Info.plist not found: $release_app" >&2
  exit 1
fi

assert_plist_value() {
  local key="$1"
  local expected="$2"
  local actual
  actual="$(plutil -extract "$key" raw "$release_plist")"
  if [[ "$actual" != "$expected" ]]; then
    echo "$key expected '$expected', found '$actual'" >&2
    exit 1
  fi
}

assert_plist_value CFBundleIdentifier com.marynavdovenko.HAHealthSync
assert_plist_value CFBundleShortVersionString 1.0.0
assert_plist_value CFBundleVersion 1
assert_plist_value MinimumOSVersion 18.0
assert_plist_value UIDeviceFamily 1
assert_plist_value BGTaskSchedulerPermittedIdentifiers.0 com.marynavdovenko.HAHealthSync.refresh

for required_path in \
  "$release_app/HAHealthSync" \
  "$release_app/PrivacyInfo.xcprivacy" \
  "$release_app/Metadata.appintents" \
  "$release_app/Assets.car"; do
  if [[ ! -e "$required_path" ]]; then
    echo "required release artifact missing: $required_path" >&2
    exit 1
  fi
done

prototype_files="$(find "$release_app" -type f -name '*.prototype.html' -print)"
if [[ -n "$prototype_files" ]]; then
  echo "local HTML prototypes must not ship in the app bundle:" >&2
  echo "$prototype_files" >&2
  exit 1
fi

echo "Release bundle verified: com.marynavdovenko.HAHealthSync 1.0.0 (1), iOS 18, iPhone"
