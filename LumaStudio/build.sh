#!/bin/zsh
set -euo pipefail

script_dir=${0:A:h}
workspace_dir=${script_dir:h}
app_dir="$workspace_dir/outputs/Luma Studio.app"
cache_dir="$workspace_dir/work/module-cache"

mkdir -p "$app_dir/Contents/MacOS" "$app_dir/Contents/Resources" "$cache_dir"
cp "$script_dir/Info.plist" "$app_dir/Contents/Info.plist"

python3 "$script_dir/create_icon.py"
iconset="$workspace_dir/work/AppIcon.iconset"
mkdir -p "$iconset"
for size in 16 32 128 256 512; do
    sips -s format png -z "$size" "$size" "$script_dir/AppIcon-1024.png" --out "$iconset/icon_${size}x${size}.png" >/dev/null
    doubled=$((size * 2))
    sips -s format png -z "$doubled" "$doubled" "$script_dir/AppIcon-1024.png" --out "$iconset/icon_${size}x${size}@2x.png" >/dev/null
done
python3 "$script_dir/create_icns.py" "$iconset" "$app_dir/Contents/Resources/AppIcon.icns"

for architecture in arm64 x86_64; do
    CLANG_MODULE_CACHE_PATH="$cache_dir" SWIFT_MODULE_CACHE_PATH="$cache_dir" \
    swiftc -disable-sandbox -parse-as-library -swift-version 5 \
        -target "${architecture}-apple-macos14.0" -O \
        "$script_dir/Sources/LumaStudio.swift" \
        -o "$workspace_dir/work/LumaStudio-$architecture"
done
lipo -create "$workspace_dir/work/LumaStudio-arm64" "$workspace_dir/work/LumaStudio-x86_64" \
    -output "$app_dir/Contents/MacOS/LumaStudio"

codesign --force --deep --sign - "$app_dir"
print "Built: $app_dir"
