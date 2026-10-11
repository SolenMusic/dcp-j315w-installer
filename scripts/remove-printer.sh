#!/bin/bash
# SPDX-License-Identifier: MIT
set -euo pipefail
export PATH=/usr/bin:/bin:/usr/sbin:/sbin
[[ $# == 0 && $EUID == 0 ]] || exit 2
root=/Library/Printers/DCPJ315WCUPS
[[ ! -L $root && -x $root/uninstall.sh ]] || { echo 'Printing driver is absent, or the installation path is unsafe.' >&2; exit 1; }
lpstat -r >/dev/null
uses_driver() {
  awk -v filter="$root/rastertodcpj315w" '/^\*cupsFilter:/ && index($0, " " filter "\"") {found=1} END {exit !found}' "$1"
}
queues=()
for ppd in /etc/cups/ppd/*.ppd; do
  [[ -f $ppd ]] || continue
  if uses_driver "$ppd"; then
    queue=$(basename "$ppd" .ppd)
    [[ $queue =~ ^[A-Za-z0-9_.-]+$ && $queue != -* ]] || exit 1
    pending=$(lpstat -W not-completed -o "$queue")
    [[ -z $pending ]] || { echo "Queue $queue has unfinished jobs. Finish or cancel them first." >&2; exit 1; }
    queues+=("$queue")
  fi
done
# The final upstream removal deletes its own script, so execute a staged copy.
stage=$(mktemp -d /private/tmp/dcpj315w-remove.XXXXXX)
trap 'rm -rf "$stage"' EXIT
cp "$root/uninstall.sh" "$stage/uninstall.sh"
if ((${#queues[@]})); then
  for queue in "${queues[@]}"; do /bin/sh "$stage/uninstall.sh" --queue "$queue"; done
else
  # An absent queue lets upstream remove unused files without touching a foreign
  # queue that happens to use the usual DCP_J315W name. No queue is created.
  queue=DCP_J315W_InstallerRemoval
  while lpstat -p "$queue" >/dev/null 2>&1; do queue=${queue}_x; done
  /bin/sh "$stage/uninstall.sh" --queue "$queue"
fi
