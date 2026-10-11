#!/bin/bash
# SPDX-License-Identifier: MIT
set -euo pipefail
root=$(cd -- "$(dirname -- "$0")" && pwd)
[[ $(uname -s) == Darwin ]] || exit 1
version=$(cat "$root/VERSION")
app="$root/build/DCP-J315W Setup.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources/scripts"
cp -X "$root/app/Info.plist" "$app/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $version" "$app/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $version" "$app/Contents/Info.plist"
cp -X "$root/scripts/"*.sh "$app/Contents/Resources/scripts/"
for arch in arm64 x86_64; do
  xcrun clang -std=c11 -fobjc-arc -O2 -Wall -Wextra -Werror -Wno-deprecated-declarations \
    -arch "$arch" -mmacosx-version-min=11.0 "$root/app/setup.m" -framework AppKit \
    -o "$root/build/setup-$arch"
done
binary_temp=$(mktemp "$app/Contents/MacOS/.DCPJ315WSetup.XXXXXX")
trap 'rm -f "$binary_temp"' EXIT
lipo -create "$root/build/setup-arm64" "$root/build/setup-x86_64" -output "$binary_temp"
chmod 755 "$binary_temp"
mv -f "$binary_temp" "$app/Contents/MacOS/DCPJ315WSetup"
for arch in arm64 x86_64; do lipo "$app/Contents/MacOS/DCPJ315WSetup" -verify_arch "$arch"; done
chmod 755 "$app/Contents/MacOS/DCPJ315WSetup" "$app/Contents/Resources/scripts/"*.sh
if [[ -n ${APPLICATION_SIGN_IDENTITY:-} ]]; then
  codesign --force --sign "$APPLICATION_SIGN_IDENTITY" --options runtime --timestamp "$app"
else codesign --force --sign - "$app"; fi
codesign --verify --strict "$app"
printf '%s\n' "$app"
