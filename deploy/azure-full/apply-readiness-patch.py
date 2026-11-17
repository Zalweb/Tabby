"""Apply only the two reviewed consent fixes after sealed backup/rehearsal.

Run on the approved migration VM. No plaintext dump is written to disk; backup
is wrapped to the operator recovery key and verified in the existing private
Blob container. --commit additionally requires the verified backup digest.
"""
import argparse
import base64
import hashlib
import json
import os
import re
import subprocess
import urllib.parse
import urllib.request
from pathlib import Path
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import padding
from cryptography.hazmat.primitives.ciphers.aead import AESGCM

APPROVED = {
    '20261113000001': '6e4013f751d85e1e62e99e7439498f8ea8d29b7e8e0f544528cd09f1bc640bf1',
    '20261113000002': 'a960f4cb56619d7a1ad307ceaaeba89f86bffc5c834f1a274bb55e8fe012776d',
}
HOST = 'sttabby7abf436e20261113.blob.core.windows.net'
ROOT = Path('/srv/tabby/migration/readiness-patches')


def validate_packet(packet):
    if not re.fullmatch(r'readiness-\d{8}T\d{6}Z-[a-f0-9]{8}', packet['run_id']):
        raise ValueError('Invalid scoped run ID')
    migrations = packet['migrations']
    if [m['version'] for m in migrations] != list(APPROVED):
        raise ValueError('Only the two reviewed migrations are allowed')
    for migration in migrations:
        if not re.fullmatch(r'[a-z_]+', migration['name']):
            raise ValueError('Invalid migration name')
        if hashlib.sha256(migration['sql'].encode()).hexdigest() != APPROVED[migration['version']]:
            raise ValueError('Migration source differs from reviewed SHA256')
        if len(re.findall(r'^BEGIN;\r?$', migration['sql'], re.M)) != 1 or len(re.findall(r'^COMMIT;\r?$', migration['sql'], re.M)) != 1:
            raise ValueError('Unexpected transaction wrapper')
    url = urllib.parse.urlparse(packet['backup_url'])
    query = urllib.parse.parse_qs(url.query)
    expected = '/migration-private/' + packet['run_id'] + '-prepatch.sealed.json'
    if url.scheme != 'https' or url.hostname != HOST or url.path != expected or url.username or url.fragment:
        raise ValueError('Backup destination is outside approved private container')
    if set(query.get('sp', [''])[0]) != set('rcw') or query.get('spr') != ['https']:
        raise ValueError('Backup SAS must be HTTPS read/create/write only')
    if not packet['recovery_public_key'].startswith('-----BEGIN PUBLIC KEY-----'):
        raise ValueError('Operator public recovery key required')


def snapshot_sql():
    pairs = []
    for table in ('transactions', 'transaction_participants', 'payments', 'payment_proofs'):
        pairs.append("'%s',encode(sha256(convert_to(coalesce((SELECT jsonb_agg(to_jsonb(t) ORDER BY to_jsonb(t)::text) FROM public.%s t),'[]'::jsonb)::text,'UTF8')),'hex')" % (table, table))
    return 'jsonb_build_object(' + ','.join(pairs) + ')'


def patch_sql(packet, commit=False):
    validate_packet(packet)
    parts = ["BEGIN ISOLATION LEVEL REPEATABLE READ;", "SET LOCAL search_path=pg_catalog,public,extensions;", "SELECT pg_advisory_xact_lock(hashtextextended('tabby-readiness-schema-patch',0));"]
    parts.append("""DO $pre$ BEGIN
      IF (SELECT count(*) FROM supabase_migrations.schema_migrations)<>50
        OR (SELECT max(version) FROM supabase_migrations.schema_migrations)<>'20261104000002'
        OR EXISTS(SELECT 1 FROM supabase_migrations.schema_migrations WHERE version IN ('20261113000001','20261113000002'))
        OR NOT has_table_privilege('authenticated','public.friendships','INSERT')
      THEN RAISE EXCEPTION 'Unexpected reviewed migration precondition'; END IF;
    END; $pre$;""")
    parts.append('CREATE TEMP TABLE tabby_readiness_before ON COMMIT DROP AS SELECT ' + snapshot_sql() + ' AS fingerprint;')
    for migration in packet['migrations']:
        body = re.sub(r'^BEGIN;\r?\n', '', migration['sql'], count=1, flags=re.M)
        body = re.sub(r'^COMMIT;\s*$', '', body, count=1, flags=re.M)
        parts.append(body)
        tag = '$tabby_source_' + migration['version'] + '$'
        if tag in body:
            raise ValueError('Unexpected migration source delimiter')
        parts.append("INSERT INTO supabase_migrations.schema_migrations(version,name,statements) VALUES ('%s','%s',ARRAY[%s%s%s]);" % (migration['version'], migration['name'], tag, body, tag))
    parts.append("DO $post$ BEGIN IF " + snapshot_sql() + " IS DISTINCT FROM (SELECT fingerprint FROM tabby_readiness_before) THEN RAISE EXCEPTION 'Financial history changed'; END IF; IF has_table_privilege('authenticated','public.friendships','INSERT') OR (SELECT count(*) FROM supabase_migrations.schema_migrations)<>52 THEN RAISE EXCEPTION 'Security patch postcondition failed'; END IF; END; $post$;")
    parts.append("SELECT jsonb_build_object('migration_count',52,'authenticated_friendship_insert',false,'financial_history_unchanged',true,'financial_fingerprints'," + snapshot_sql() + ');')
    if commit:
        parts.append("NOTIFY pgrst, 'reload schema';")
    parts.append('COMMIT;' if commit else 'ROLLBACK;')
    return '\n'.join(parts)


def psql(sql, folder):
    result = subprocess.run(['docker', 'exec', '-i', 'supabase-db', 'psql', '-X', '-qAt', '-v', 'ON_ERROR_STOP=1', '-v', 'VERBOSITY=sqlstate', '-U', 'supabase_admin', '-d', 'postgres'], input=sql.encode(), capture_output=True, timeout=120)
    if result.returncode:
        (folder / 'private-sql-error.log').write_bytes(result.stderr)
        raise RuntimeError('Database operation failed; private SQLSTATE log retained')
    rows = [line for line in result.stdout.decode().splitlines() if line.startswith('{')]
    return json.loads(rows[-1]) if rows else {}


def main():
    os.umask(0o077)
    parser = argparse.ArgumentParser()
    parser.add_argument('--packet', required=True)
    parser.add_argument('--mode', choices=['prepare', 'commit'], required=True)
    parser.add_argument('--verified-backup-sha256')
    args = parser.parse_args()
    encoded = Path(args.packet).read_bytes()
    digest = hashlib.sha256(encoded).hexdigest()
    envelope = json.loads(encoded)
    private = serialization.load_pem_private_key(Path('/srv/tabby/migration-private.pem').read_bytes(), password=None)
    key = private.decrypt(base64.b64decode(envelope['wrappedKey']), padding.OAEP(mgf=padding.MGF1(hashes.SHA256()), algorithm=hashes.SHA256(), label=None))
    packet = json.loads(AESGCM(key).decrypt(base64.b64decode(envelope['iv']), base64.b64decode(envelope['ciphertext']) + base64.b64decode(envelope['tag']), None))
    validate_packet(packet)
    folder = ROOT / packet['run_id']
    folder.mkdir(parents=True, exist_ok=True, mode=0o700)
    report = {'packet_sha256': digest, 'run_id': packet['run_id'], 'mode': args.mode, 'outcome': 'failed'}
    stage = 'preconditions'
    try:
        if args.mode == 'prepare':
            state = psql("BEGIN READ ONLY; SELECT jsonb_build_object('migration_count',(SELECT count(*) FROM supabase_migrations.schema_migrations),'latest_version',(SELECT max(version) FROM supabase_migrations.schema_migrations),'client_insert',has_table_privilege('authenticated','public.friendships','INSERT')); ROLLBACK;", folder)
            if state != {'migration_count': 50, 'latest_version': '20261104000002', 'client_insert': True}:
                raise ValueError('Destination differs from reviewed catalog')
            stage = 'encrypted-backup'
            backup = subprocess.check_output(['docker', 'exec', 'supabase-db', 'pg_dump', '-U', 'supabase_admin', '-d', 'postgres', '--format=custom'], stderr=subprocess.PIPE, timeout=180)
            if not backup.startswith(b'PGDMP') or len(backup) > 128 * 1024 * 1024:
                raise ValueError('Invalid or oversized database backup')
            listing = subprocess.run(['docker', 'exec', '-i', 'supabase-db', 'pg_restore', '--list'], input=backup, capture_output=True, timeout=60)
            if listing.returncode:
                raise ValueError('Database backup cannot be inspected by pg_restore')
            public = serialization.load_pem_public_key(packet['recovery_public_key'].encode())
            backup_key, iv = os.urandom(32), os.urandom(12)
            encrypted = AESGCM(backup_key).encrypt(iv, backup, None)
            wrapped = public.encrypt(backup_key, padding.OAEP(mgf=padding.MGF1(hashes.SHA256()), algorithm=hashes.SHA256(), label=None))
            sealed = json.dumps({'version': 1, 'algorithm': 'RSA-OAEP-SHA256+A256GCM', 'wrappedKey': base64.b64encode(wrapped).decode(), 'iv': base64.b64encode(iv).decode(), 'tag': base64.b64encode(encrypted[-16:]).decode(), 'ciphertext': base64.b64encode(encrypted[:-16]).decode()}).encode()
            backup_path = folder / 'database-prepatch.sealed.json'
            with backup_path.open('xb') as output:
                output.write(sealed)
                output.flush()
                os.fsync(output.fileno())
            report['backup'] = {'ciphertext_sha256': hashlib.sha256(sealed).hexdigest(), 'plaintext_sha256': hashlib.sha256(backup).hexdigest(), 'encrypted_bytes': len(sealed), 'pg_restore_list': 'passed', 'blob_name': packet['run_id'] + '-prepatch.sealed.json'}
            stage = 'private-off-vm-backup'
            request = urllib.request.Request(packet['backup_url'], data=sealed, method='PUT', headers={'x-ms-blob-type': 'BlockBlob', 'Content-Type': 'application/json'})
            with urllib.request.urlopen(request, timeout=60) as response:
                if response.status != 201:
                    raise RuntimeError('Private backup upload not acknowledged')
            with urllib.request.urlopen(packet['backup_url'], timeout=60) as response:
                remote = response.read(len(sealed) + 1)
            if hashlib.sha256(remote).digest() != hashlib.sha256(sealed).digest():
                raise RuntimeError('Off-VM encrypted backup differs')
            report['backup']['off_vm_verified'] = True
            stage = 'rollback-rehearsal'
            report['database'] = psql(patch_sql(packet), folder)
        else:
            prior = json.loads((folder / 'prepare-report.json').read_text())
            if prior['outcome'] != 'passed' or prior['packet_sha256'] != digest or args.verified_backup_sha256 != prior['backup']['ciphertext_sha256']:
                raise ValueError('Identical packet needs rehearsal and verified operator backup recovery')
            stage = 'atomic-commit'
            report['backup'] = prior['backup']
            report['database'] = psql(patch_sql(packet, commit=True), folder)
        report['outcome'] = 'passed'
    except Exception as error:
        report['stage'] = stage
        report['error_type'] = type(error).__name__
    (folder / (args.mode + '-report.json')).write_text(json.dumps(report))
    print(json.dumps(report), flush=True)
    return 0 if report['outcome'] == 'passed' else 2


if __name__ == '__main__':
    raise SystemExit(main())
