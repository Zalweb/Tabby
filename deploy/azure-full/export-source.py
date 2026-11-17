"""Protected source export using official CLI filters and one PG snapshot."""
import base64
import hashlib
import io
import json
import os
import re
import subprocess
import tarfile
from pathlib import Path
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import padding
from cryptography.hazmat.primitives.ciphers.aead import AESGCM

os.umask(0o077)
root = Path('/srv/tabby/migration')
envelope = json.loads((root / 'export-capsule.json').read_text())
if envelope['version'] != 1 or envelope['algorithm'] != 'RSA-OAEP-SHA256+A256GCM':
    raise SystemExit('Unsupported encrypted transfer envelope.')
private = serialization.load_pem_private_key(Path('/srv/tabby/migration-private.pem').read_bytes(), password=None)
key = private.decrypt(base64.b64decode(envelope['wrappedKey']), padding.OAEP(mgf=padding.MGF1(hashes.SHA256()), algorithm=hashes.SHA256(), label=None))
packet = json.loads(AESGCM(key).decrypt(base64.b64decode(envelope['iv']), base64.b64decode(envelope['ciphertext']) + base64.b64decode(envelope['tag']), None))
if not re.fullmatch(r'run-[a-zA-Z0-9]+', packet['run_id']):
    raise SystemExit('Invalid export identifier.')
folder = root / packet['run_id']
folder.mkdir(mode=0o700)
scripts = folder / 'scripts'
scripts.mkdir(mode=0o700)
env_files = []
holder = None


def env_file(mode, extra=None):
    values = {**packet['env'], **packet['options'][mode], **(extra or {})}
    if any('\n' in str(value) or '\r' in str(value) or '\0' in str(value) for value in values.values()):
        raise ValueError('Invalid environment value.')
    target = folder / f'{mode}.env'
    target.write_text('\n'.join(f'{name}={value}' for name, value in values.items()) + '\n')
    env_files.append(target)
    return target


def docker(env, *arguments):
    return ['docker', 'exec', '-i', '--user', '0', '--env-file', str(env), 'supabase-db', *arguments]


try:
    certificate = folder / 'source-ca.crt'
    certificate.write_text(packet['source_ca'])
    subprocess.run(['docker', 'cp', str(certificate), 'supabase-db:/tmp/tabby-source-ca.crt'], check=True, capture_output=True)
    base_env = env_file('data')
    connect = subprocess.run(docker(base_env, 'psql', '-X', '-qAt', '-v', 'ON_ERROR_STOP=1', '-c',
        "select json_build_object('version',current_setting('server_version'),'auth_users',(select count(*) from auth.users),'expenses',(select count(*) from public.transactions),'payments',(select count(*) from public.payments))"), capture_output=True, timeout=40)
    if connect.returncode:
        (folder / 'connection-error.txt').write_bytes(connect.stderr)
        print(json.dumps({'stage': 'source-connection', 'outcome': 'failed', 'detail': 'See private connection-error file; no credential value logged.'}))
        raise SystemExit(2)
    source = json.loads(connect.stdout)
    (folder / 'source-counts.json').write_text(json.dumps(source))
    print(json.dumps({'stage': 'source-connection', 'outcome': 'passed', **source}), flush=True)
    for mode, script in packet['scripts'].items():
        (scripts / f'{mode}.sh').write_text(script)
    subprocess.run(['docker', 'cp', str(scripts), 'supabase-db:/tmp/tabby-export-scripts'], check=True, capture_output=True)
    holder_error = open(folder / 'snapshot-holder-error.txt', 'wb')
    holder = subprocess.Popen(docker(base_env, 'psql', '-X', '-qAt', '-v', 'ON_ERROR_STOP=1'), stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=holder_error, text=True)
    holder.stdin.write("BEGIN ISOLATION LEVEL REPEATABLE READ READ ONLY;\nSELECT pg_export_snapshot();\n")
    holder.stdin.flush()
    snapshot = holder.stdout.readline().strip()
    if not re.fullmatch(r'[0-9A-Fa-f-]+', snapshot):
        raise RuntimeError('Source snapshot was not established.')
    fingerprint_sql = """
SELECT format('SELECT ''HASH '' || jsonb_build_object(''schema'',%L,''table'',%L,''count'',count(*),''hash'',md5(coalesce(string_agg(md5(to_jsonb(t)::text),'''' ORDER BY md5(to_jsonb(t)::text)),'''')))::text FROM %I.%I t;',n.nspname,c.relname,n.nspname,c.relname)
FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
WHERE n.nspname IN ('public','auth','storage','supabase_functions') AND c.relkind IN ('r','p')
AND NOT (n.nspname='auth' AND c.relname='schema_migrations')
AND NOT (n.nspname='storage' AND c.relname='migrations')
AND NOT (n.nspname='supabase_functions' AND c.relname='migrations') ORDER BY n.nspname,c.relname
\\gexec
SELECT 'SNAPSHOT_READY';
"""
    holder.stdin.write(fingerprint_sql)
    holder.stdin.flush()
    fingerprints = []
    for line in holder.stdout:
        if line.strip() == 'SNAPSHOT_READY':
            break
        if line.startswith('HASH '):
            fingerprints.append(json.loads(line[5:]))
    if holder.poll() is not None or not fingerprints:
        raise RuntimeError('Source snapshot fingerprint capture failed.')
    (folder / 'fingerprints.json').write_text(json.dumps(fingerprints, indent=2))
    manifest = {'run_id': packet['run_id'], 'cli_version': packet['cli_version'], 'snapshot': snapshot, 'source': source, 'tables': len(fingerprints), 'files': {}}
    for mode in ['roles', 'schema', 'data']:
        flags = {} if mode == 'roles' else {'EXTRA_FLAGS': '--snapshot=' + snapshot}
        env = env_file(mode, flags)
        output = folder / f'{mode}.sql'
        with open(output, 'wb') as dump, open(folder / f'{mode}-error.txt', 'wb') as error:
            result = subprocess.run(docker(env, 'bash', f'/tmp/tabby-export-scripts/{mode}.sh'), stdout=dump, stderr=error, timeout=300)
        if result.returncode:
            raise RuntimeError(f'{mode} export failed; private error output retained.')
        manifest['files'][mode] = {'bytes': output.stat().st_size, 'sha256': hashlib.sha256(output.read_bytes()).hexdigest()}
        print(json.dumps({'stage': mode, 'outcome': 'passed', 'bytes': output.stat().st_size}), flush=True)
    holder.stdin.write('ROLLBACK;\n\\q\n')
    holder.stdin.flush()
    holder.wait(timeout=15)
    (folder / 'manifest.json').write_text(json.dumps(manifest, indent=2))
    archive_bytes = io.BytesIO()
    with tarfile.open(fileobj=archive_bytes, mode='w:gz') as archive:
        for name in ['roles.sql', 'schema.sql', 'data.sql', 'fingerprints.json', 'manifest.json']:
            archive.add(folder / name, arcname=name)
    archive_key, iv = os.urandom(32), os.urandom(12)
    sealed = AESGCM(archive_key).encrypt(iv, archive_bytes.getvalue(), None)
    wrapped = private.public_key().encrypt(archive_key, padding.OAEP(mgf=padding.MGF1(hashes.SHA256()), algorithm=hashes.SHA256(), label=None))
    package = {'version': 1, 'algorithm': 'RSA-OAEP-SHA256+A256GCM', 'wrappedKey': base64.b64encode(wrapped).decode(), 'iv': base64.b64encode(iv).decode(), 'tag': base64.b64encode(sealed[-16:]).decode(), 'ciphertext': base64.b64encode(sealed[:-16]).decode()}
    (folder / 'database-backup.sealed.json').write_text(json.dumps(package))
    (root / 'latest-export.json').write_text(json.dumps({'run_id': packet['run_id'], 'folder': str(folder), 'source': source, 'tables': len(fingerprints)}))
    print(json.dumps({'stage': 'consistent-export', 'outcome': 'passed', 'run_id': packet['run_id'], 'tables': len(fingerprints), 'backup_encrypted': True}), flush=True)
except SystemExit:
    raise
except Exception as error:
    print(json.dumps({'stage': 'consistent-export', 'outcome': 'failed', 'detail': str(error) if isinstance(error, RuntimeError) else type(error).__name__}), flush=True)
    raise SystemExit(3)
finally:
    if holder and holder.poll() is None:
        holder.stdin.close()
        holder.wait(timeout=20)
    for credential in env_files:
        credential.unlink(missing_ok=True)
