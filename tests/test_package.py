#!/usr/bin/env python3
"""Read-only package checks; safe on a personal Mac."""
from pathlib import Path
import plistlib
import subprocess
import sys
import tempfile
import xml.etree.ElementTree as ET
root=Path(__file__).resolve().parents[1]
package=Path(sys.argv[1]).resolve()
def run(*args):
    return subprocess.run(args,capture_output=True,text=True,check=True,timeout=60).stdout
with tempfile.TemporaryDirectory() as tmp:
    folder=Path(tmp)
    run('pkgutil','--expand-full',str(package),str(folder/'expanded'))
    expanded=folder/'expanded'
    xml=ET.parse(expanded/'Distribution').getroot()
    assert xml.find('options').get('customize')=='always'
    choices={x.get('id'):x for x in xml.findall('choice')}
    assert set(choices)=={'printing','scanning','tools'}
    assert choices['printing'].get('start_selected')=='true' and choices['scanning'].get('start_selected')=='true'
    for p,s in [(1,1),(1,0),(0,1),(0,0)]:
        change=folder/'choices.plist'
        change.write_bytes(plistlib.dumps([{'choiceIdentifier':name,'choiceAttribute':'selected','attributeSetting':value} for name,value in [('printing',p),('scanning',s)]]))
        output=run('installer','-showChoicesAfterApplyingChangesXML',str(change),'-pkg',str(package),'-target','/')
        tree=plistlib.loads(output[output.index('<?xml'):].encode())
        states={item['choiceIdentifier']:item['attributeSetting'] for item in tree if item['choiceAttribute']=='selected'}
        assert states['printing']==p and states['scanning']==s
        assert states['tools']==bool(p or s)
    print('PASS: real Installer evaluates printing-only, scanning-only, both, and no-component selections')
    printing=expanded/'printing-component.pkg/Payload/Library/Printers/DCPJ315WCUPS'
    scanner=expanded/'scanner-component.pkg/Payload/Library/Application Support/DCPJ315WInstaller/Scanner'
    tools=expanded/'tools-component.pkg/Payload/Applications/DCP-J315W Setup.app'
    assert (printing/'rastertodcpj315w').exists() and (scanner/'build/DCPJ315WAirScanBridge.app').is_dir() and tools.is_dir()
    for path in [printing/'rastertodcpj315w',scanner/'build/DCPJ315WAirScanBridge.app',tools]: run('codesign','--verify','--strict',str(path))
    for path in [printing/'rastertodcpj315w',scanner/'build/DCPJ315WAirScanBridge.app/Contents/MacOS/DCPJ315WAirScanBridge',tools/'Contents/MacOS/DCPJ315WSetup']:
        for arch in ['arm64','x86_64']: run('lipo',str(path),'-verify_arch',arch)
    for name in ['scanner-component.pkg','tools-component.pkg']:
        info=ET.parse(expanded/name/'PackageInfo').getroot()
        for bundle in info.findall('.//relocate/bundle'): raise AssertionError(f'Relocatable bundle: {name}')
    for name in ['Welcome.html','Conclusion.html','License.html']:
        page=(expanded/'Resources'/name).read_text()
        assert '<meta charset="utf-8">' in page and '-apple-system' in page and 'â†' not in page
    print('PASS: component payloads preserve universal signatures, fixed locations, UTF-8 and system fonts')
