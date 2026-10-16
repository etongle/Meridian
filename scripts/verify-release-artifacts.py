#!/usr/bin/env python3
"""Validate a local Keychain-signed release before publishing it from Actions."""
import json
import os
import re
import subprocess
import sys
import zipfile
import plistlib
from pathlib import Path

folder = Path(sys.argv[1])
metadata = json.loads((folder / 'release.json').read_text())
config = json.loads(Path('Config/release.json').read_text())
source = metadata['sourceCommit']
tag = metadata['tag']
assert re.fullmatch(r'[0-9a-f]{40}', source), 'Invalid source commit'
assert tag == 'v' + config['version'], 'Version mismatch'
subprocess.run(['git', 'merge-base', '--is-ancestor', source, 'origin/main'], check=True)
source_config = subprocess.check_output(['git', 'show', source + ':Config/release.json'])
assert json.loads(source_config) == config, 'Source config differs from staging'
archive = folder / ('Meridian-' + config['version'] + '-macOS.zip')
with zipfile.ZipFile(archive) as z:
    info = plistlib.loads(z.read('Meridian.app/Contents/Info.plist'))
    for field, expected in {
        'CFBundleShortVersionString': config['version'],
        'CFBundleVersion': config['build'],
        'SUPublicEDKey': config['sparklePublicKey'],
        'SUFeedURL': config['feedURL'],
    }.items():
        assert info[field] == expected, 'App configuration mismatch: ' + field
    for filename in ['LICENSE', 'NOTICE', 'THIRD_PARTY_NOTICES.md']:
        expected = subprocess.check_output(['git', 'show', source + ':' + filename])
        assert (folder / filename).read_bytes() == expected, 'Release notice mismatch'
        assert z.read('Meridian.app/Contents/Resources/' + filename) == expected, 'Bundled notice mismatch'
if 'GITHUB_OUTPUT' in os.environ:
    with open(os.environ['GITHUB_OUTPUT'], 'a') as f:
        f.write('tag=' + tag + '\nsource=' + source + '\n')
print('Validated source commit, app configuration and bundled license notices.')
