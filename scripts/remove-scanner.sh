#!/bin/bash
# SPDX-License-Identifier: MIT
set -euo pipefail
[[ $# == 0 && $(id -u) != 0 ]] || exit 2
label=org.dcpj315w.scan.airscan
support="$HOME/Library/Application Support/DCPJ315WScan"
plist="$HOME/Library/LaunchAgents/$label.plist"
[[ ! -L $support && ! -L $plist ]] || { echo 'Refusing a symlink installation target.' >&2; exit 1; }
if launchctl print "gui/$(id -u)/$label" >/dev/null 2>&1; then launchctl bootout "gui/$(id -u)/$label"; fi
rm -f -- "$plist"
rm -rf -- "$support/DCPJ315WAirScanBridge.app"
echo 'Removed scanning for this user. Saved scans and diagnostic logs were preserved.'
