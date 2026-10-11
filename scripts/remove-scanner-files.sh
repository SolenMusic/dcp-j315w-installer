#!/bin/bash
# SPDX-License-Identifier: MIT
set -euo pipefail
export PATH=/usr/bin:/bin:/usr/sbin:/sbin
[[ $# == 0 && $EUID == 0 ]] || exit 2
root='/Library/Application Support/DCPJ315WInstaller/Scanner'
[[ ! -L $root ]] || { echo 'Refusing a symlink installation target.' >&2; exit 1; }
if [[ -d $root ]]; then
  rm -rf -- "$root/build/DCPJ315WAirScanBridge.app"
  for name in install-macos-airscan.sh uninstall-macos-airscan.sh LICENSE README.md CHANGELOG.md VERSION; do rm -f "$root/$name"; done
  rm -f "$root/macos/README.md"
  rmdir "$root/macos" "$root/build" "$root" 2>/dev/null || true
fi
if pkgutil --pkg-info org.dcpj315w.installer.scanner >/dev/null 2>&1; then pkgutil --forget org.dcpj315w.installer.scanner >/dev/null; fi
echo 'Removed shared scanner installation files. Other users’ configured private helpers were preserved.'
