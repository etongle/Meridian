#!/usr/bin/env python3
import json
import plistlib
import sys
from pathlib import Path

config = json.loads(Path(sys.argv[1]).read_text())
info = {
    'CFBundleExecutable': 'Meridian', 'CFBundleIdentifier': config['bundleIdentifier'],
    'CFBundleIconFile': 'AppIcon', 'CFBundleName': 'Meridian', 'CFBundleDisplayName': 'Meridian', 'CFBundlePackageType': 'APPL',
    'CFBundleShortVersionString': config['version'], 'CFBundleVersion': config['build'],
    'LSMinimumSystemVersion': '14.0', 'LSUIElement': True, 'LSMultipleInstancesProhibited': True, 'NSHighResolutionCapable': True,
    'NSPrincipalClass': 'NSApplication', 'CFBundleDevelopmentRegion': 'en',
    'CFBundleLocalizations': ['en', 'zh-Hans'], 'NSHumanReadableCopyright': 'Meridian · 2026',
    'SUEnableAutomaticChecks': True, 'SUAutomaticallyUpdate': False, 'SUScheduledCheckInterval': 21600,
    'SUVerifyUpdateBeforeExtraction': True,
}
if config['feedURL'] and config['sparklePublicKey']:
    info.update(SUFeedURL=config['feedURL'], SUPublicEDKey=config['sparklePublicKey'])
Path(sys.argv[2]).write_bytes(plistlib.dumps(info))
