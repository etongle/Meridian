#!/usr/bin/env python3
import json
import re
import sys
from pathlib import Path

repository, tag, public_key = sys.argv[1:]
p = Path(__file__).resolve().parents[1] / 'Config/release.json'
config = json.loads(p.read_text())
if not re.fullmatch(r'v\d+\.\d+\.\d+', tag):
    raise SystemExit('Release tags must use vMAJOR.MINOR.PATCH')
if tag != 'v' + config['version']:
    raise SystemExit('Tag and Config/release.json version must match; increment build for every release.')
config['repository'] = repository
config['feedURL'] = f'https://github.com/{repository}/releases/latest/download/appcast.xml'
config['sparklePublicKey'] = public_key
p.write_text(json.dumps(config, indent=2) + '\n')
