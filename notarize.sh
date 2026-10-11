#!/bin/bash
# SPDX-License-Identifier: MIT
set -euo pipefail
[[ $# == 2 ]] || { echo 'Usage: ./notarize.sh PACKAGE.pkg KEYCHAIN_PROFILE' >&2; exit 1; }
package=$1; profile=$2
pkgutil --check-signature "$package"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
xcrun notarytool submit "$package" --keychain-profile "$profile" --output-format plist > "$work/result.plist"
id=$(/usr/libexec/PlistBuddy -c 'Print :id' "$work/result.plist")
echo "Notarization submission: $id"
if ! xcrun notarytool wait "$id" --keychain-profile "$profile" --timeout 60s --output-format plist > "$work/result.plist"; then
  echo "Resume this submission with notarytool wait $id; do not resubmit." >&2; exit 1
fi
[[ $(/usr/libexec/PlistBuddy -c 'Print :status' "$work/result.plist") == Accepted ]] || { echo 'Notarization failed; do not publish.' >&2; exit 1; }
xcrun stapler staple "$package"
xcrun stapler validate "$package"
spctl --assess --type install --verbose "$package"
