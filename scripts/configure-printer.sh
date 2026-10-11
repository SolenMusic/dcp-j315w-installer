#!/bin/bash
# SPDX-License-Identifier: MIT
set -euo pipefail
export PATH=/usr/bin:/bin:/usr/sbin:/sbin
[[ $# == 1 && $1 =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]] || exit 2
[[ $EUID == 0 ]] || { echo 'Administrator authentication is required.' >&2; exit 1; }
exec /Library/Printers/DCPJ315WCUPS/configure.sh --address "$1"
