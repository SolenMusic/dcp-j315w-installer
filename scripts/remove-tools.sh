#!/bin/bash
# SPDX-License-Identifier: MIT
set -euo pipefail
export PATH=/usr/bin:/bin:/usr/sbin:/sbin
[[ $# == 0 && $EUID == 0 ]] || exit 2
[[ ! -e /Library/Printers/DCPJ315WCUPS/rastertodcpj315w && ! -d '/Library/Application Support/DCPJ315WInstaller/Scanner' ]] || {
  echo 'Remove the printing driver and shared scanner files first.' >&2; exit 1;
}
app='/Applications/DCP-J315W Setup.app'
[[ ! -L $app ]] || exit 1
if [[ -d $app ]]; then
  identifier=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$app/Contents/Info.plist")
  [[ $identifier == org.dcpj315w.installer.setup ]] || exit 1
  rm -rf -- "$app"
fi
rmdir '/Library/Application Support/DCPJ315WInstaller' 2>/dev/null || true
if pkgutil --pkg-info org.dcpj315w.installer.tools >/dev/null 2>&1; then pkgutil --forget org.dcpj315w.installer.tools >/dev/null; fi
