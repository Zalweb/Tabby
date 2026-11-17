"""Transactionally rehearse the sealed source dump on the empty destination.

Never emits dump contents or database errors (which can contain private rows).
The default mode always rolls back. A separate, explicit --commit is required.
"""
import argparse
import hashlib
import json
import os
import re
import subprocess
from pathlib import Path

os.umask(0o077)
parser = argparse.ArgumentParser()
parser.add_argument('--commit', action='store_true')
args = parser.parse_args()
root = Path('/srv/tabby/migration')
latest = json.loads((root / 'latest-export.json').read_text())
if not re.fullmatch(r'run-[a-zA-Z0-9]+', latest['run_id']):
    raise SystemExit('Invalid export identifier.')
folder = root / latest['run_id']
manifest = json.loads((folder / 'manifest.json').read_text())
if args.commit:
    rehearsal = json.loads((folder / 'restore-rehearsal.json').read_text())
    if rehearsal.get('outcome') != 'passed' or rehearsal.get('fingerprint_tables') != latest['tables'] or rehearsal.get('mismatches') != []:
        raise SystemExit('A successful full-parity rollback rehearsal is required before commit.')
command = ['docker', 'exec', '-i', 'supabase-db', 'psql', '-X', '-qAt', '-U', 'supabase_admin', '-d', 'postgres', '-v', 'ON_ERROR_STOP=1']
guard = subprocess.run(command + ['-c', "SELECT json_build_object('users',(SELECT count(*) FROM auth.users),'objects',(SELECT count(*) FROM storage.objects),'public_tables',(SELECT count(*) FROM pg_tables WHERE schemaname='public'))"], capture_output=True, check=True)
counts = json.loads(guard.stdout)
if any(counts.values()):
    raise SystemExit('Destination is not empty; refusing to overlay source data.')
parts = [b'BEGIN;\nCREATE SCHEMA IF NOT EXISTS vault;\n']
for mode in ['roles', 'schema', 'data']:
    contents = (folder / f'{mode}.sql').read_bytes()
    if hashlib.sha256(contents).hexdigest() != manifest['files'][mode]['sha256']:
        raise SystemExit('Dump integrity validation failed.')
    parts.append(contents)
    parts.append(b'\n')
fingerprints = json.loads((folder / 'fingerprints.json').read_text())
for table in fingerprints:
    schema, name = table['schema'], table['table']
    if not all(re.fullmatch(r'[a-zA-Z0-9_]+', value) for value in [schema, name]):
        raise SystemExit('Unsupported table identifier.')
    parts.append((f"SELECT 'HASH ' || jsonb_build_object('schema','{schema}','table','{name}','count',count(*),'hash',md5(coalesce(string_agg(md5(to_jsonb(t)::text),'' ORDER BY md5(to_jsonb(t)::text)),'')))::text FROM \"{schema}\".\"{name}\" t;\n").encode())
parts.append(b'COMMIT;\n' if args.commit else b'ROLLBACK;\n')
mode = 'commit' if args.commit else 'rehearsal'
with open(folder / f'restore-{mode}-error.txt', 'wb') as error:
    result = subprocess.run(command, input=b''.join(parts), stdout=subprocess.PIPE, stderr=error, timeout=180)
report = {'stage': 'restore-' + mode, 'outcome': 'passed' if result.returncode == 0 else 'failed', 'transaction': 'committed' if args.commit and not result.returncode else 'rolled back', 'run_id': latest['run_id']}
if not result.returncode:
    actual = [json.loads(line[5:]) for line in result.stdout.decode().splitlines() if line.startswith('HASH ')]
    (folder / f'restore-{mode}-fingerprints.json').write_text(json.dumps(actual))
    source_by_table = {(row['schema'], row['table']): row for row in fingerprints}
    mismatches = [row['schema'] + '.' + row['table'] for row in actual if row != source_by_table[(row['schema'], row['table'])]]
    report['fingerprint_tables'] = len(actual)
    report['mismatches'] = mismatches
    if len(actual) != len(fingerprints) or mismatches:
        report['outcome'] = 'failed-parity'
if result.returncode:
    # Only identifiers from specific schema errors are safe to emit. Other
    # PostgreSQL errors can include emails, row contents or credential values.
    for line in (folder / f'restore-{mode}-error.txt').read_text().splitlines():
        if 'ERROR:' in line:
            detail = line.split('ERROR:', 1)[1].strip()
            if re.fullmatch(r'(?:relation|column|schema|type|role|extension|function) "[a-zA-Z0-9_.]+" (?:does not exist|already exists|is not available)', detail):
                report['schema_error'] = detail
            break
(folder / f'restore-{mode}.json').write_text(json.dumps(report))
print(json.dumps(report), flush=True)
raise SystemExit(0 if report['outcome'] == 'passed' else 2)
