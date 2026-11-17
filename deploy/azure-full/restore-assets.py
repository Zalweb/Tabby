"""Restore media through Storage HTTP and reconcile original object ownership."""
import base64
import hashlib
import json
import os
import subprocess
import urllib.parse
import urllib.request
from pathlib import Path
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import padding
from cryptography.hazmat.primitives.ciphers.aead import AESGCM

os.umask(0o077)
root = Path('/srv/tabby/migration')
folder = Path(json.loads((root / 'latest-export.json').read_text())['folder'])
private = serialization.load_pem_private_key(Path('/srv/tabby/migration-private.pem').read_bytes(), password=None)
envelope = json.loads((root / 'source-assets.sealed.json').read_text())
key = private.decrypt(base64.b64decode(envelope['wrappedKey']), padding.OAEP(mgf=padding.MGF1(hashes.SHA256()), algorithm=hashes.SHA256(), label=None))
snapshot = json.loads(AESGCM(key).decrypt(base64.b64decode(envelope['iv']), base64.b64decode(envelope['ciphertext']) + base64.b64decode(envelope['tag']), None))
values = dict(line.split('=', 1) for line in Path('/srv/tabby/.env').read_text().splitlines() if line and not line.startswith('#') and '=' in line)
origin, service = values['SUPABASE_PUBLIC_URL'], values['SERVICE_ROLE_KEY']
command = ['docker', 'exec', '-i', 'supabase-db', 'psql', '-X', '-qAt', '-U', 'supabase_admin', '-d', 'postgres', '-v', 'ON_ERROR_STOP=1']


def sql(query):
    result = subprocess.run(command, input=query.encode(), capture_output=True)
    if result.returncode:
        (folder / 'media-error.txt').write_bytes(result.stderr)
        raise RuntimeError('Private media reconciliation SQL failed.')
    return result.stdout.decode().strip()


def literal(value):
    return 'NULL' if value is None else "'" + str(value).replace("'", "''") + "'"


saved_path = folder / 'media-original-metadata.json'
if not saved_path.exists():
    saved_path.write_text(sql("SELECT coalesce(json_agg(t),'[]') FROM (SELECT id,bucket_id,name,owner,owner_id,created_at,metadata,user_metadata FROM storage.objects) t;"))
originals = json.loads(saved_path.read_text())
verified = []
stage = 'media-upload'
try:
    for obj in snapshot['objects']:
        original = next(row for row in originals if row['id'] == obj['id'] and row['bucket_id'] == obj['bucket_id'] and row['name'] == obj['name'])
        data = base64.b64decode(obj['bytes_base64'])
        if hashlib.sha256(data).hexdigest() != obj['sha256']:
            raise RuntimeError('Encrypted source asset hash mismatch.')
        url = origin + '/storage/v1/object/' + urllib.parse.quote(obj['bucket_id'], safe='') + '/' + urllib.parse.quote(obj['name'], safe='/')
        headers = {'apikey': service, 'Authorization': 'Bearer ' + service}
        request = urllib.request.Request(url, data=data, method='POST', headers={**headers, 'x-upsert': 'true', 'Content-Type': obj['metadata'].get('mimetype', 'application/octet-stream')})
        with urllib.request.urlopen(request, timeout=45) as response:
            if response.status not in [200, 201]:
                raise RuntimeError('Storage upload was not acknowledged.')
        stage = 'media-download-verification'
        with urllib.request.urlopen(urllib.request.Request(url, headers=headers), timeout=45) as response:
            downloaded = response.read(16777217)
        if hashlib.sha256(downloaded).hexdigest() != obj['sha256'] or len(downloaded) != len(data):
            raise RuntimeError('Restored media content mismatch.')
        stage = 'media-ownership-reconciliation'
        metadata = literal(json.dumps(original['metadata']))
        user_metadata = literal(json.dumps(original['user_metadata'])) if original['user_metadata'] is not None else 'NULL'
        result = sql(f"UPDATE storage.objects SET owner={literal(original['owner'])}::uuid,owner_id={literal(original['owner_id'])},created_at={literal(original['created_at'])}::timestamptz,metadata={metadata}::jsonb,user_metadata={user_metadata}::jsonb WHERE id={literal(original['id'])}::uuid AND bucket_id={literal(original['bucket_id'])} AND name={literal(original['name'])} RETURNING json_build_object('same_id',id={literal(original['id'])}::uuid,'same_owner',owner IS NOT DISTINCT FROM {literal(original['owner'])}::uuid,'same_owner_id',owner_id IS NOT DISTINCT FROM {literal(original['owner_id'])});")
        check = json.loads(result.splitlines()[0])
        if not all(check.values()):
            raise RuntimeError('Restored media identity mismatch.')
        verified.append({'id': obj['id'], 'sha256': obj['sha256'], 'bytes': len(data), **check})
        stage = 'media-upload'
    (folder / 'media-verification-private.json').write_text(json.dumps(verified))
    print(json.dumps({'stage': 'media-restore', 'outcome': 'passed', 'objects': len(verified), 'hashes_match': True, 'ids_and_ownership_match': True}), flush=True)
except Exception as error:
    reason = getattr(error, 'reason', None)
    error_code = None
    if isinstance(error, urllib.error.HTTPError):
        body = error.read()
        (folder / 'media-http-error.json').write_bytes(body)
        try:
            parsed = json.loads(body)
            error_code = parsed.get('error') or parsed.get('code')
        except ValueError:
            pass
    print(json.dumps({'stage': stage, 'outcome': 'failed', 'error_type': type(error).__name__, 'http_status': getattr(error, 'code', None), 'reason_type': type(reason).__name__, 'errno': getattr(reason, 'errno', None), 'os_error': getattr(reason, 'strerror', None), 'certificate_error': getattr(reason, 'verify_message', None), 'storage_error_code': error_code}), flush=True)
    raise SystemExit(2)
