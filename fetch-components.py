#!/usr/bin/env python3
"""Developer-only download and SHA256 verification of pinned public releases."""
from pathlib import Path
import hashlib
import json
import urllib.request
import os
import tempfile
root = Path(__file__).resolve().parent
folder = root/'build/downloads'; folder.mkdir(parents=True, exist_ok=True)
for component in json.loads((root/'components.json').read_text()).values():
    dest = folder/component['asset']
    if dest.is_file() and hashlib.sha256(dest.read_bytes()).hexdigest() == component['sha256']:
        print(f'Verified cached {dest.name}'); continue
    url = f"https://github.com/{component['repository']}/releases/download/v{component['version']}/{component['asset']}"
    fd, name = tempfile.mkstemp(dir=folder)
    try:
        with os.fdopen(fd,'wb') as out, urllib.request.urlopen(url, timeout=60) as response:
            while chunk := response.read(65536): out.write(chunk)
        assert hashlib.sha256(Path(name).read_bytes()).hexdigest() == component['sha256'], 'Checksum mismatch'
        os.replace(name,dest)
        print(f'Downloaded and verified {dest.name}')
    finally:
        Path(name).unlink(missing_ok=True)
