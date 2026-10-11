#!/bin/bash
# SPDX-License-Identifier: MIT
set -euo pipefail
export COPYFILE_DISABLE=1
root=$(cd -- "$(dirname -- "$0")" && pwd)
unsigned=0
[[ $# == 0 || ( $# == 1 && $1 == --unsigned ) ]] || { echo 'Usage: ./build-installer.sh [--unsigned]' >&2; exit 1; }
[[ $# == 0 ]] || unsigned=1
[[ $(uname -s) == Darwin ]] || exit 1
version=$(cat "$root/VERSION")
work=$(mktemp -d /private/tmp/dcpj315w-combined-build.XXXXXX)
trap 'rm -rf "$work"' EXIT
# Manifest validation and artifact verification are independent of download.
python3 - "$root" <<'PY'
from pathlib import Path
import hashlib,json,sys
root=Path(sys.argv[1]); manifest=json.loads((root/'components.json').read_text())
for item in manifest.values():
    artifact=root/'build/downloads'/item['asset']
    assert artifact.is_file() and hashlib.sha256(artifact.read_bytes()).hexdigest()==item['sha256'], f'Invalid artifact: {artifact}'
PY
printing=$(plutil -extract printing.asset raw -o - "$root/components.json")
scanning=$(plutil -extract scanning.asset raw -o - "$root/components.json")
pkgutil --check-signature "$root/build/downloads/$printing"
pkgutil --expand "$root/build/downloads/$printing" "$work/printing-product"
cp -R "$work/printing-product/driver.pkg" "$work/printing.pkg"
# pkgutil expansion is a directory; flatten it back into the original component.
pkgutil --flatten "$work/printing.pkg" "$work/printing-component.pkg"
tar -xzf "$root/build/downloads/$scanning" -C "$work"
scan_root="$work/dcp-j315w-scan-macos-universal-$(plutil -extract scanning.version raw -o - "$root/components.json")"
scanner_payload="$work/scanner-root/Library/Application Support/DCPJ315WInstaller/Scanner"
mkdir -p "$scanner_payload"
cp -RX "$scan_root/." "$scanner_payload/"
codesign --verify --strict "$scanner_payload/build/DCPJ315WAirScanBridge.app"
xcrun stapler validate "$scanner_payload/build/DCPJ315WAirScanBridge.app"
find "$work/scanner-root" -type d -exec chmod 755 {} +
pkgbuild --analyze --root "$work/scanner-root" "$work/scanner-bundles.plist"
python3 - "$work/scanner-bundles.plist" <<'PY'
import plistlib,sys
path=sys.argv[1]
with open(path,'rb') as f: bundles=plistlib.load(f)
for bundle in bundles:
    bundle['BundleIsRelocatable']=False
    bundle['BundleIsVersionChecked']=False
with open(path,'wb') as f: plistlib.dump(bundles,f)
PY
pkgbuild --root "$work/scanner-root" --ownership recommended --identifier org.dcpj315w.installer.scanner \
  --component-plist "$work/scanner-bundles.plist" --version "$(plutil -extract scanning.version raw -o - "$root/components.json")" --install-location / "$work/scanner-component.pkg"
mkdir -p "$work/tools-root/Applications"
cp -RX "$root/build/DCP-J315W Setup.app" "$work/tools-root/Applications/"
pkgbuild --analyze --root "$work/tools-root" "$work/tools-bundles.plist"
python3 - "$work/tools-bundles.plist" <<'PY'
import plistlib,sys
path=sys.argv[1]
with open(path,'rb') as f: bundles=plistlib.load(f)
for bundle in bundles:
    bundle['BundleIsRelocatable']=False
    bundle['BundleIsVersionChecked']=False
with open(path,'wb') as f: plistlib.dump(bundles,f)
PY
pkgbuild --root "$work/tools-root" --ownership recommended --identifier org.dcpj315w.installer.tools \
  --component-plist "$work/tools-bundles.plist" --version "$version" --install-location / "$work/tools-component.pkg"
mkdir -p "$work/resources" "$root/dist"
cp -X "$root/resources/"*.html "$work/resources/"
python3 - "$root" "$work" "$scan_root" <<'PY'
from pathlib import Path
import html,sys
root,work,scan=map(Path,sys.argv[1:])
header=(root/'resources/Welcome.html').read_text().split('<body>',1)[0]+'<body>'
license=(root/'LICENSE').read_text()
(work/'resources/License.html').write_text(header+'<h1>MIT License</h1>'+''.join('<p>'+html.escape(p).replace('\n',' ')+'</p>' for p in license.split('\n\n'))+'<p>The bundled printing and scanning components retain their own MIT copyright notices, included in their installed LICENSE files.</p></body></html>')
PY
python3 - "$root" "$work" <<'PY'
from pathlib import Path
import json,sys
root,work=map(Path,sys.argv[1:]); v=(root/'VERSION').read_text().strip(); c=json.loads((root/'components.json').read_text())
(work/'distribution.xml').write_text(f'''<?xml version="1.0" encoding="UTF-8"?>
<installer-gui-script minSpecVersion="2">
<title>DCP-J315W Printing and Scanning {v}</title>
<welcome file="Welcome.html" mime-type="text/html"/>
<license file="License.html" mime-type="text/html"/>
<conclusion file="Conclusion.html" mime-type="text/html"/>
<options customize="always" require-scripts="false" hostArchitectures="x86_64,arm64"/>
<domains enable_localSystem="true" enable_currentUserHome="false" enable_anywhere="false"/>
<allowed-os-versions><os-version min="11.0"/></allowed-os-versions>
<choices-outline><line choice="printing"/><line choice="scanning"/><line choice="tools"/></choices-outline>
<choice id="printing" title="Printing" description="CUPS printing over Wi-Fi at 300/600 dpi." start_selected="true"><pkg-ref id="org.dcp-j315w-cups.driver"/></choice>
<choice id="scanning" title="Scanning" description="Native Image Capture scanning over Wi-Fi at 100/300 dpi. Configure your account in DCP-J315W Setup." start_selected="true"><pkg-ref id="org.dcpj315w.installer.scanner"/></choice>
<choice id="tools" title="DCP-J315W Setup" visible="false" selected="choices['printing'].selected || choices['scanning'].selected"><pkg-ref id="org.dcpj315w.installer.tools"/></choice>
<pkg-ref id="org.dcp-j315w-cups.driver" version="{c['printing']['version']}" auth="Root">printing-component.pkg</pkg-ref>
<pkg-ref id="org.dcpj315w.installer.scanner" version="{c['scanning']['version']}" auth="Root">scanner-component.pkg</pkg-ref>
<pkg-ref id="org.dcpj315w.installer.tools" version="{v}" auth="Root">tools-component.pkg</pkg-ref>
</installer-gui-script>
''')
PY
suffix=
args=(--distribution "$work/distribution.xml" --resources "$work/resources" --package-path "$work")
if ((unsigned)); then suffix=-unsigned
else : "${INSTALLER_SIGN_IDENTITY:?Set Developer ID Installer identity}"; args+=(--sign "$INSTALLER_SIGN_IDENTITY"); fi
output="$root/dist/dcp-j315w-installer-$version-macos-universal$suffix.pkg"
productbuild "${args[@]}" "$output"
if ((!unsigned)); then pkgutil --check-signature "$output"; fi
printf '%s\n' "$output"
