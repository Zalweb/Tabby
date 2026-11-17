"""Reconcile source-managed custom objects/history and rehearse pending SQL.

The default invocation rolls back the entire upgrade. --commit requires a
successful rehearsal of the identical encrypted packet and ledger invariants.
"""
import argparse
import base64
import hashlib
import gzip
import json
import os
import re
import subprocess
from pathlib import Path
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import padding
from cryptography.hazmat.primitives.ciphers.aead import AESGCM

os.umask(0o077)
parser = argparse.ArgumentParser()
parser.add_argument('--commit', action='store_true')
args = parser.parse_args()
root = Path('/srv/tabby/migration')
latest = json.loads((root / 'latest-export.json').read_text())
folder = Path(latest['folder'])
envelope_bytes = (root / 'upgrade-capsule.json').read_bytes()
digest = hashlib.sha256(envelope_bytes).hexdigest()
envelope = json.loads(envelope_bytes)
private = serialization.load_pem_private_key(Path('/srv/tabby/migration-private.pem').read_bytes(), password=None)
key = private.decrypt(base64.b64decode(envelope['wrappedKey']), padding.OAEP(mgf=padding.MGF1(hashes.SHA256()), algorithm=hashes.SHA256(), label=None))
packet = json.loads(gzip.decompress(AESGCM(key).decrypt(base64.b64decode(envelope['iv']), base64.b64decode(envelope['ciphertext']) + base64.b64decode(envelope['tag']), None)))
inventory = packet['inventory']
if args.commit:
    prior = json.loads((folder / 'upgrade-rehearsal.json').read_text())
    if prior.get('outcome') != 'passed' or prior.get('packet_sha256') != digest:
        raise SystemExit('The identical packet needs a successful rollback rehearsal.')


def ident(value):
    return '"' + value.replace('"', '""') + '"'


def literal(value):
    return "'" + value.replace("'", "''") + "'"


parts = ['BEGIN;', 'SET search_path=public,extensions,pg_catalog;']
parts += ['CREATE SCHEMA IF NOT EXISTS supabase_migrations;', 'CREATE TABLE IF NOT EXISTS supabase_migrations.schema_migrations(version text PRIMARY KEY,statements text[],name text);']
history_json = json.dumps(inventory['history'])
parts.append(f"INSERT INTO supabase_migrations.schema_migrations(version,statements,name) SELECT version,statements,name FROM jsonb_to_recordset({literal(history_json)}::jsonb) AS t(version text,statements text[],name text);")
for policy in inventory['policies']:
    table = ident(policy['schemaname']) + '.' + ident(policy['tablename'])
    parts.append(f"DROP POLICY IF EXISTS {ident(policy['policyname'])} ON {table};")
    roles = ','.join('PUBLIC' if role == 'public' else ident(role) for role in policy['roles'])
    statement = f"CREATE POLICY {ident(policy['policyname'])} ON {table} AS {policy['permissive']} FOR {policy['cmd']} TO {roles}"
    if policy['qual']:
        statement += ' USING (' + policy['qual'] + ')'
    if policy['with_check']:
        statement += ' WITH CHECK (' + policy['with_check'] + ')'
    parts.append(statement + ';')
for trigger in inventory['triggers']:
    parts.append(f"DROP TRIGGER IF EXISTS {ident(trigger['name'])} ON {ident(trigger['schema'])}.{ident(trigger['table'])};")
    parts.append(trigger['definition'] + ';')
for event in inventory['event_triggers']:
    if event['name'] != 'ensure_rls' or event['function'] not in ['rls_auto_enable()', 'public.rls_auto_enable()'] or event['event'] != 'ddl_command_end':
        raise SystemExit('Unreviewed custom event trigger.')
    parts.append('DROP EVENT TRIGGER IF EXISTS ensure_rls;')
    parts.append("CREATE EVENT TRIGGER ensure_rls ON ddl_command_end WHEN TAG IN ('CREATE TABLE','CREATE TABLE AS','SELECT INTO') EXECUTE FUNCTION public.rls_auto_enable();")
for member in inventory['publications']:
    schema, table = member['schemaname'], member['tablename']
    parts.append(f"DO $publication$ BEGIN IF NOT EXISTS(SELECT 1 FROM pg_publication_tables WHERE pubname='supabase_realtime' AND schemaname={literal(schema)} AND tablename={literal(table)}) THEN ALTER PUBLICATION supabase_realtime ADD TABLE {ident(schema)}.{ident(table)}; END IF; END $publication$;")

for migration in packet['migrations']:
    lines = migration['sql'].splitlines()
    # These repository files use transaction wrappers only at their boundaries;
    # fail rather than removing a procedural or middle transaction statement.
    for index, line in enumerate(lines):
        if line.strip() == 'BEGIN;' and index >= 10:
            raise SystemExit('Unexpected inner BEGIN transaction.')
        if line.strip() == 'COMMIT;' and index < len(lines) - 10:
            raise SystemExit('Unexpected inner COMMIT transaction.')
    sql = '\n'.join(line for line in lines if line.strip() not in ['BEGIN;', 'COMMIT;'])
    parts.append(sql)
    version, name = migration['file'][:-4].split('_', 1)
    parts.append(f"INSERT INTO supabase_migrations.schema_migrations(version,name,statements) VALUES({literal(version)},{literal(name)},ARRAY[{literal(migration['sql'])}]);")
    parts.append(f"SELECT 'MIGRATION {version}';")

source_fingerprints = json.loads((folder / 'fingerprints.json').read_text())
data = (folder / 'data.sql').read_text()
for name in ['transactions', 'transaction_participants', 'payments']:
    match = re.search(r'^COPY "public"\."' + name + r'" \(([^\n]+)\) FROM stdin;$', data, re.MULTILINE)
    if not match:
        raise SystemExit('Original financial column projection is missing.')
    columns = match.group(1)
    if not re.fullmatch(r'"[a-zA-Z0-9_]+"(?:, "[a-zA-Z0-9_]+")*', columns):
        raise SystemExit('Unsupported original financial columns.')
    expected = next(row for row in source_fingerprints if row['schema'] == 'public' and row['table'] == name)
    parts.append(f"DO $invariant$ DECLARE actual text; rows bigint; BEGIN SELECT count(*),md5(coalesce(string_agg(md5(to_jsonb(t)::text),'' ORDER BY md5(to_jsonb(t)::text)),'')) INTO rows,actual FROM (SELECT {columns} FROM public.{ident(name)}) t; IF rows<>{int(expected['count'])} OR actual<>{literal(expected['hash'])} THEN RAISE EXCEPTION 'Original financial invariant failed'; END IF; END $invariant$;")
parts.append("SELECT 'HISTORY ' || count(*) FROM supabase_migrations.schema_migrations;")
parts.append("NOTIFY pgrst, 'reload schema'; NOTIFY pgrst, 'reload config';")
parts.append('COMMIT;' if args.commit else 'ROLLBACK;')
mode = 'commit' if args.commit else 'rehearsal'
command = ['docker', 'exec', '-i', 'supabase-db', 'psql', '-X', '-qAt', '-U', 'supabase_admin', '-d', 'postgres', '-v', 'ON_ERROR_STOP=1']
with open(folder / f'upgrade-{mode}-error.txt', 'wb') as error:
    result = subprocess.run(command, input='\n'.join(parts).encode(), stdout=subprocess.PIPE, stderr=error, timeout=240)
report = {'stage': 'upgrade-' + mode, 'outcome': 'passed' if result.returncode == 0 else 'failed', 'transaction': 'committed' if args.commit and result.returncode == 0 else 'rolled back', 'packet_sha256': digest, 'pending': len(packet['migrations']), 'preserved_financial_tables': 3}
output = result.stdout.decode().splitlines()
report['completed_versions'] = [line[10:] for line in output if line.startswith('MIGRATION ')]
report['history_count'] = next((int(line[8:]) for line in output if line.startswith('HISTORY ')), None)
if result.returncode:
    for line in (folder / f'upgrade-{mode}-error.txt').read_text().splitlines():
        if 'ERROR:' in line:
            detail = line.split('ERROR:', 1)[1].strip()
            if re.fullmatch(r'(?:relation|column|schema|type|role|extension|function) "[a-zA-Z0-9_.]+" (?:does not exist|already exists|is not available)', detail):
                report['schema_error'] = detail
            elif detail == 'Original financial invariant failed':
                report['schema_error'] = detail
            break
(folder / f'upgrade-{mode}.json').write_text(json.dumps(report))
print(json.dumps(report), flush=True)
raise SystemExit(0 if result.returncode == 0 else 2)
