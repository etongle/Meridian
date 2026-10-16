"""Cross-process tests: duplicate launch, independent identity and crash recovery."""
import subprocess
import sys
import tempfile
from pathlib import Path

probe = str(Path(sys.argv[1]).resolve())
with tempfile.TemporaryDirectory() as directory:
    lock = str(Path(directory) / 'meridian.lock')
    owner = subprocess.Popen([probe, lock, '--hold'], stdin=subprocess.PIPE, stdout=subprocess.PIPE, text=True)
    try:
        assert owner.stdout.readline().strip() == 'ready'
        assert subprocess.run([probe, lock]).returncode == 23, 'Second process acquired the lock'
        assert subprocess.run([probe, str(Path(directory) / 'preview.lock')]).returncode == 0
        owner.kill()
        owner.wait(timeout=5)
        assert subprocess.run([probe, lock]).returncode == 0, 'Crash left a stale lock'
    finally:
        if owner.poll() is None:
            owner.kill()
            owner.wait(timeout=5)
print('Passed single-instance checks: duplicate rejected, identities isolated, crash lock released.')
