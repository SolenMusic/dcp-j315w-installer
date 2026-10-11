#!/bin/bash
# SPDX-License-Identifier: MIT
set -euo pipefail
[[ $# == 1 && $(id -u) != 0 ]] || exit 2
exec /bin/bash '/Library/Application Support/DCPJ315WInstaller/Scanner/install-macos-airscan.sh' --address "$1"
