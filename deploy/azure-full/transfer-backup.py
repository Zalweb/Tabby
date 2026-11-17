"""Transfer only sealed backup/media/key-recovery packages to private Blob."""
import base64
import hashlib
import json
import os
import urllib.request
from pathlib import Path
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import padding
from cryptography.hazmat.primitives.ciphers.aead import AESGCM

os.umask(0o077)
root = Path('/srv/tabby/migration')
private = serialization.load_pem_private_key(Path('/srv/tabby/migration-private.pem').read_bytes(), password=None)
envelope = json.loads((root / 'transfer-capsule.json').read_text())
key = private.decrypt(base64.b64decode(envelope['wrappedKey']), padding.OAEP(mgf=padding.MGF1(hashes.SHA256()), algorithm=hashes.SHA256(), label=None))
config = json.loads(AESGCM(key).decrypt(base64.b64decode(envelope['iv']), base64.b64decode(envelope['ciphertext']) + base64.b64decode(envelope['tag']), None))
latest = json.loads((root / 'latest-export.json').read_text())
folder = Path(latest['folder'])
stage = 'encrypted-media-download'
try:
    with urllib.request.urlopen(config['asset_url'], timeout=40) as response:
        assets = response.read(16777217)
    if len(assets) > 16777216:
        raise RuntimeError('Encrypted media package exceeds transfer bound.')
    (root / 'source-assets.sealed.json').write_bytes(assets)
    stage = 'off-vm-database-backup'
    backup = (folder / 'database-backup.sealed.json').read_bytes()
    for url, contents in [(config['backup_url'], backup)]:
        request = urllib.request.Request(url, data=contents, method='PUT', headers={'x-ms-blob-type': 'BlockBlob', 'Content-Type': 'application/json'})
        with urllib.request.urlopen(request, timeout=40) as response:
            if response.status != 201:
                raise RuntimeError('Private backup upload was not acknowledged.')
    stage = 'off-vm-key-recovery'
    recovery_public = serialization.load_pem_public_key(config['recovery_public_key'].encode())
    recovery_key, iv = os.urandom(32), os.urandom(12)
    sealed = AESGCM(recovery_key).encrypt(iv, Path('/srv/tabby/migration-private.pem').read_bytes(), None)
    wrapped = recovery_public.encrypt(recovery_key, padding.OAEP(mgf=padding.MGF1(hashes.SHA256()), algorithm=hashes.SHA256(), label=None))
    recovery = json.dumps({'version': 1, 'algorithm': 'RSA-OAEP-SHA256+A256GCM', 'wrappedKey': base64.b64encode(wrapped).decode(), 'iv': base64.b64encode(iv).decode(), 'tag': base64.b64encode(sealed[-16:]).decode(), 'ciphertext': base64.b64encode(sealed[:-16]).decode()}).encode()
    request = urllib.request.Request(config['recovery_url'], data=recovery, method='PUT', headers={'x-ms-blob-type': 'BlockBlob', 'Content-Type': 'application/json'})
    with urllib.request.urlopen(request, timeout=40) as response:
        if response.status != 201:
            raise RuntimeError('Private recovery upload was not acknowledged.')
    report = {'stage': 'protected-transfer', 'outcome': 'passed', 'database_sha256': hashlib.sha256(backup).hexdigest(), 'database_bytes': len(backup), 'media_sha256': hashlib.sha256(assets).hexdigest(), 'recovery_bytes': len(recovery), 'blob_public_access': False}
    (folder / 'backup-transfer.json').write_text(json.dumps(report))
    print(json.dumps(report), flush=True)
except Exception as error:
    print(json.dumps({'stage': stage, 'outcome': 'failed', 'error_type': type(error).__name__}), flush=True)
    raise SystemExit(2)
