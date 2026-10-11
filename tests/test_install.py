#!/usr/bin/env python3
"""Actual component installation/removal on a disposable GitHub runner ONLY."""
from pathlib import Path
import os
import plistlib
import subprocess
import sys
import tempfile
assert sys.platform=='darwin' and os.geteuid()==0 and os.environ.get('GITHUB_ACTIONS')=='true', 'Disposable GitHub macOS runner only'
root=Path(__file__).resolve().parents[1]
package=Path(sys.argv[1]).resolve()
printing=Path('/Library/Printers/DCPJ315WCUPS')
scanner=Path('/Library/Application Support/DCPJ315WInstaller/Scanner')
app=Path('/Applications/DCP-J315W Setup.app')
scripts=app/'Contents/Resources/scripts'
queue='DCP_J315W_CombinedTest'
foreign='DCP_J315W_CombinedForeign'
def cmd(*args,check=True):
    result=subprocess.run(args,capture_output=True,text=True,timeout=120)
    if check and result.returncode:
        print(result.stdout,result.stderr,flush=True);result.check_returncode()
    return result
assert not printing.exists() and not scanner.exists() and not app.exists()
with tempfile.TemporaryDirectory() as tmp:
    change=Path(tmp)/'choices.plist'
    def install(p,s):
        change.write_bytes(plistlib.dumps([{'choiceIdentifier':n,'choiceAttribute':'selected','attributeSetting':v} for n,v in [('printing',p),('scanning',s)]]))
        cmd('installer','-pkg',str(package),'-target','/','-applyChoiceChangesXML',str(change))
    def remove_tools(): cmd('/bin/bash',str(scripts/'remove-tools.sh'))
    install(1,0)
    assert printing.exists() and app.exists() and not scanner.exists()
    # Use localhost port 9; no physical printer and no printing occurs.
    cmd(str(printing/'configure.sh'),'--queue',queue,'--address','127.0.0.1','--port','9')
    cmd('lpadmin','-p',foreign,'-E','-v','socket://127.0.0.1:9','-m','raw')
    cmd('lpadmin','-p',queue,'-o','PageSize=A5','-o','Resolution=600dpi','-o','ColorModel=Color')
    settings=cmd('lpoptions','-p',queue,'-l').stdout
    install(1,0)
    assert cmd('lpoptions','-p',queue,'-l').stdout==settings
    note=Path(tmp)/'held.txt';note.write_text('Held test job; never print.\n')
    cmd('lp','-d',queue,'-H','hold',str(note))
    assert cmd('/bin/bash',str(scripts/'remove-printer.sh'),check=False).returncode!=0
    assert printing.exists() and cmd('lpstat','-p',queue).returncode==0
    cmd('cancel',queue)
    cmd('/bin/bash',str(scripts/'remove-printer.sh'))
    assert not printing.exists() and cmd('lpstat','-p',foreign).returncode==0
    cmd('lpadmin','-x',foreign)
    remove_tools();assert not app.exists()
    print('PASS: printing-only install, upgrade, held-job refusal, driver removal and foreign queue preservation',flush=True)
    install(0,1)
    assert scanner.exists() and app.exists() and not printing.exists()
    cmd('codesign','--verify','--strict',str(scanner/'build/DCPJ315WAirScanBridge.app'))
    cmd('/bin/bash',str(scripts/'remove-scanner-files.sh'))
    assert not scanner.exists()
    remove_tools();assert not app.exists()
    print('PASS: scanning-only installs the shared source without a printing queue; shared removal clears its receipt',flush=True)
    install(1,1)
    assert printing.exists() and scanner.exists() and app.exists()
    cmd('/bin/bash',str(scripts/'remove-printer.sh'))
    assert not printing.exists() and scanner.exists()
    cmd('/bin/bash',str(scripts/'remove-scanner-files.sh'));remove_tools()
    for identifier in ['org.dcp-j315w-cups.driver','org.dcpj315w.installer.scanner','org.dcpj315w.installer.tools']:
        assert cmd('pkgutil','--pkg-info',identifier,check=False).returncode!=0
    print('PASS: combined installation and independent component removal clear all three receipts',flush=True)
