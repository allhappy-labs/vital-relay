#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
icon_dir="$repo_root/HAHealthSync/Resources/AppIcon.icon"
asset_catalog="$repo_root/HAHealthSync/Resources/Assets.xcassets"
legacy_icon="$asset_catalog/AppIcon.appiconset"

if [[ ! -d "$icon_dir" ]]; then
  echo "missing layered icon: $icon_dir" >&2
  exit 1
fi

if [[ -d "$legacy_icon" ]]; then
  echo "legacy app icon still present: $legacy_icon" >&2
  exit 1
fi

icon_json="$icon_dir/icon.json"
jq -e '
  .["supported-platforms"].squares == "shared"
  and (.groups | length == 3)
  and ([.groups[].layers[].name] == [
    "03 Health and Home",
    "02 Health to Home",
    "01 Home to Health"
  ])
' "$icon_json" >/dev/null

while IFS= read -r image_name; do
  image_path="$icon_dir/Assets/$image_name"
  xmllint --noout "$image_path"

  if [[ "$(xmllint --xpath 'string(/*[local-name()="svg"]/@viewBox)' "$image_path")" != "0 0 1024 1024" ]]; then
    echo "unexpected SVG canvas: $image_path" >&2
    exit 1
  fi
done < <(jq -r '.groups[].layers[]."image-name"' "$icon_json")

for arrow_spec in 01-home-to-health.svg:return-ribbon 02-health-to-home.svg:send-ribbon; do
  arrow_name="${arrow_spec%%:*}"
  ribbon_id="${arrow_spec#*:}"
  arrow_path="$icon_dir/Assets/$arrow_name"
  ribbon_fill_count="$(xmllint --xpath "count(/*[local-name()='svg']/*[local-name()='g']/*[local-name()='path'][@fill='url(#$ribbon_id)'])" "$arrow_path")"
  ribbon_stroke_count="$(xmllint --xpath "count(/*[local-name()='svg']/*[local-name()='g']/*[local-name()='path'][@stroke='url(#$ribbon_id)'])" "$arrow_path")"

  if [[ "$ribbon_fill_count" != "1" || "$ribbon_stroke_count" != "0" ]]; then
    echo "arrow must use one continuous filled ribbon silhouette: $arrow_path" >&2
    exit 1
  fi
done

compile_dir="$(mktemp -d /tmp/ha-app-icon.XXXXXX)"
cleanup() {
  rm -rf -- "$compile_dir"
}
trap cleanup EXIT

mkdir -p "$compile_dir/output"

if ! xcrun actool \
  "$icon_dir" \
  "$asset_catalog" \
  --compile "$compile_dir/output" \
  --output-format human-readable-text \
  --notices \
  --warnings \
  --output-partial-info-plist "$compile_dir/icon-info.plist" \
  --app-icon AppIcon \
  --accent-color AccentColor \
  --compress-pngs \
  --development-region en \
  --target-device iphone \
  --minimum-deployment-target 18.0 \
  --platform iphonesimulator \
  --bundle-identifier com.marynavdovenko.HAHealthSync \
  >"$compile_dir/actool.log" 2>&1
then
  cat "$compile_dir/actool.log" >&2
  exit 1
fi

if grep -Eq '(/\* com\.apple\.actool\.errors \*/|warning:)' "$compile_dir/actool.log"; then
  cat "$compile_dir/actool.log" >&2
  exit 1
fi

[[ "$(plutil -extract CFBundleIcons.CFBundlePrimaryIcon.CFBundleIconName raw "$compile_dir/icon-info.plist")" == "AppIcon" ]]
[[ "$(sips -g pixelWidth "$compile_dir/output/AppIcon60x60@2x.png" | awk '/pixelWidth/ { print $2 }')" == "120" ]]
[[ "$(sips -g pixelHeight "$compile_dir/output/AppIcon76x76@2x~ipad.png" | awk '/pixelHeight/ { print $2 }')" == "152" ]]

swift "$repo_root/Tools/verify-app-icon-visual.swift" "$compile_dir/output/AppIcon60x60@2x.png"

xcrun assetutil --info "$compile_dir/output/Assets.car" > "$compile_dir/assets.json"

jq -e '
  ([.[]
    | select(.AssetType == "Icon Image" and .Name == "AppIcon")
    | (.Appearance // "default")]
    | unique
    | sort) == ["ISAppearanceTintable", "UIAppearanceDark", "default"]
  and ([.[]
    | select(.AssetType == "Icon Image" and .Name == "AppIcon")
    | select(.PixelWidth != 1024 or .PixelHeight != 1024)]
    | length == 0)
  and ([.[]
    | select(.AssetType == "IconImageStack" and .Name == "AppIcon")
    | select(.LayerCount != 4)]
    | length == 0)
  and ([.[]
    | select(.AssetType == "IconImageStack" and .Name == "AppIcon")]
    | length >= 3)
' "$compile_dir/assets.json" >/dev/null

echo "layered AppIcon compiled with default, dark, and tinted appearances"
