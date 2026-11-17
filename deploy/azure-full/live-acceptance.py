"""Real Auth-issued synthetic journeys; never exercises migrated user accounts."""
import base64
import concurrent.futures
import hashlib
import json
import os
import secrets
import subprocess
import urllib.error
import urllib.parse
import urllib.request
import uuid
from pathlib import Path

os.umask(0o077)
root = Path('/srv/tabby/migration')
env = dict(line.split('=', 1) for line in Path('/srv/tabby/.env').read_text().splitlines() if line and not line.startswith('#') and '=' in line)
origin, anon, service = env['SUPABASE_PUBLIC_URL'], env['ANON_KEY'], env['SERVICE_ROLE_KEY']
if 'eastasia.cloudapp.azure.com' not in origin:
    raise SystemExit('Only the explicit Azure migration target is supported.')
report = {'environment': origin, 'authentication': 'real GoTrue password-issued access tokens', 'fixtures': 'synthetic accounts only', 'checks': []}


def request(method, route, token=anon, body=None, data=None, extra=None):
    headers = {'apikey': anon, 'Authorization': 'Bearer ' + token, **(extra or {})}
    if body is not None:
        data = json.dumps(body).encode()
        headers['Content-Type'] = 'application/json'
    try:
        with urllib.request.urlopen(urllib.request.Request(origin + route, data=data, method=method, headers=headers), timeout=30) as response:
            contents = response.read()
            status = response.status
    except urllib.error.HTTPError as error:
        status, contents = error.code, error.read()
    try:
        return status, json.loads(contents)
    except ValueError:
        return status, contents


def check(name, passed, **evidence):
    report['checks'].append({'name': name, 'outcome': 'passed' if passed else 'failed', **evidence})
    if not passed:
        raise RuntimeError(name)


def sql(query):
    result = subprocess.run(['docker', 'exec', '-i', 'supabase-db', 'psql', '-X', '-qAt', '-U', 'supabase_admin', '-d', 'postgres', '-v', 'ON_ERROR_STOP=1'], input=query.encode(), capture_output=True)
    if result.returncode:
        (root / 'live-fixture-sql-error.txt').write_bytes(result.stderr)
        raise RuntimeError('Synthetic fixture preparation SQL')
    return result.stdout.decode().strip()


def literal(value):
    return "'" + str(value).replace("'", "''") + "'"


accounts_path = root / 'fixture-accounts.json'
accounts = json.loads(accounts_path.read_text()) if accounts_path.exists() else []
try:
    for index in range(len(accounts), 3):
        fixture = {'email': 'tabby-azure-qa-' + uuid.uuid4().hex + '@example.invalid', 'password': secrets.token_urlsafe(32)}
        status, body = request('POST', '/auth/v1/admin/users', service, {'email': fixture['email'], 'password': fixture['password'], 'email_confirm': True, 'user_metadata': {'display_name': 'Synthetic Azure QA ' + str(index)}, 'app_metadata': {'tabby_azure_fixture': True}})
        check('Auth Admin creates synthetic account ' + str(index), status in [200, 201] and bool(body.get('id')), status=status)
        fixture['id'] = body['id']
        accounts.append(fixture)
        accounts_path.write_text(json.dumps(accounts))
    tokens = []
    for index, account in enumerate(accounts):
        status, body = request('POST', '/auth/v1/token?grant_type=password', anon, {'email': account['email'], 'password': account['password']})
        check('Real Auth password sign-in ' + str(index), status == 200 and bool(body.get('access_token')) and body.get('user', {}).get('id') == account['id'], status=status)
        tokens.append(body['access_token'])
    a, b, outsider = (account['id'] for account in accounts)
    profile_status, profiles = request('GET', '/rest/v1/users?select=id&id=eq.' + a, tokens[0])
    check('Auth trigger creates the matching profile', profile_status == 200 and len(profiles) == 1 and profiles[0]['id'] == a, status=profile_status)
    baseline_path = root / 'original-financial-before-fixtures.json'
    if not baseline_path.exists():
        baseline = {}
        for table in ['transactions', 'transaction_participants', 'payments']:
            baseline[table] = json.loads(sql(f"SELECT coalesce(json_agg(t ORDER BY id),'[]') FROM public.{table} t;"))
        baseline_path.write_text(json.dumps(baseline))
    baseline = json.loads(baseline_path.read_text())
    first, second = sorted([a,b])
    tab = sql(f"SELECT id FROM public.tabs WHERE tab_type='individual' AND user_a={literal(first)}::uuid AND user_b={literal(second)}::uuid LIMIT 1;") or str(uuid.uuid4())
    sql(f"BEGIN; DO $guard$ BEGIN IF (SELECT count(*) FROM auth.users WHERE id IN ({literal(a)}::uuid,{literal(b)}::uuid,{literal(outsider)}::uuid) AND raw_app_meta_data->>'tabby_azure_fixture'='true')<>3 THEN RAISE EXCEPTION 'Synthetic fixture guard failed'; END IF; END $guard$; INSERT INTO public.friendships(requester_id,addressee_id,status) VALUES({literal(a)}::uuid,{literal(b)}::uuid,'accepted') ON CONFLICT(requester_id,addressee_id) DO UPDATE SET status='accepted'; INSERT INTO public.tabs(id,tab_type,user_a,user_b,status) VALUES({literal(tab)}::uuid,'individual',{literal(first)}::uuid,{literal(second)}::uuid,'active') ON CONFLICT(id) DO NOTHING; INSERT INTO public.tab_members(tab_id,user_id) VALUES({literal(tab)}::uuid,{literal(a)}::uuid),({literal(tab)}::uuid,{literal(b)}::uuid) ON CONFLICT DO NOTHING; COMMIT;")
    op = str(uuid.uuid4())
    command = {'p_tab_id': tab, 'p_description': 'Synthetic Azure acceptance', 'p_category': 'other', 'p_total_amount_centavos': 1000, 'p_paid_by_user_id': a, 'p_participants': [{'user_id': a, 'participant_role': 'payer', 'share_amount_centavos': 400}, {'user_id': b, 'participant_role': 'debtor', 'share_amount_centavos': 600}], 'p_due_date': None, 'p_receipt_url': None}
    status, expense = request('POST', '/rest/v1/rpc/create_expense_v1', tokens[0], {'p_operation_id': op, 'p_command': command})
    check('Member creates integer-centavo expense', status == 200 and isinstance(expense, str), status=status)
    status, replay = request('POST', '/rest/v1/rpc/create_expense_v1', tokens[0], {'p_operation_id': op, 'p_command': command})
    check('Response-loss retry returns the same expense', status == 200 and replay == expense, status=status)
    status, _ = request('POST', '/rest/v1/rpc/create_expense_v1', tokens[0], {'p_operation_id': op, 'p_command': {**command, 'p_description': 'Conflicting retry'}})
    check('Changed idempotency payload rejected', status == 400, status=status)
    status, rows = request('GET', '/rest/v1/transactions?select=id&tab_id=eq.' + tab, tokens[2])
    check('Outsider cannot read the fixture ledger', status == 200 and rows == [], status=status)
    status, _ = request('POST', '/rest/v1/rpc/create_expense_v1', tokens[2], {'p_operation_id': str(uuid.uuid4()), 'p_command': command})
    check('Outsider cannot create a fixture expense', status == 403, status=status)
    private_helper = sql("SELECT has_function_privilege('authenticated','public.get_pair_outstanding(uuid,uuid,uuid)','EXECUTE')::text;")
    check('Authenticated role cannot execute unchecked pair helper', private_helper == 'false')
    status, _ = request('POST', '/rest/v1/rpc/get_pair_outstanding', tokens[2], {'p_tab_id': tab, 'p_debtor': b, 'p_creditor': a})
    check('Unchecked pair helper is not exposed', status in [403, 404], status=status)
    status, malformed = request('POST', '/rest/v1/rpc/create_expense_v1', tokens[0], {'p_operation_id': str(uuid.uuid4()), 'p_command': {**command, 'p_total_amount_centavos': '10.1'}})
    check('Fractional centavos return a stable client error', status == 400 and malformed.get('code') == 'PT400', status=status)
    payment_command = {'p_tab_id': tab, 'p_submitted_by_user_id': b, 'p_recipient_user_id': a, 'p_amount_centavos': 600, 'p_payment_method': 'cash', 'p_note': 'Synthetic Azure confirmation race'}
    payments = []
    for _ in range(2):
        status, payment = request('POST', '/rest/v1/rpc/submit_payment_v1', tokens[1], {'p_operation_id': str(uuid.uuid4()), 'p_command': payment_command})
        check('Payer submits pending payment ' + str(len(payments)), status == 200 and isinstance(payment, str), status=status)
        payments.append(payment)
    route = '/rest/v1/rpc/get_net_balance?p_tab_id=' + tab + '&p_user_id=' + b
    status, balance = request('GET', route, tokens[1])
    check('Submission alone does not change the balance', status == 200 and abs(int(balance)) == 600, status=status)
    status, _ = request('POST', '/rest/v1/rpc/confirm_payment', tokens[1], {'p_payment_id': payments[0]})
    check('Payer cannot confirm receipt', status == 403, status=status)
    with concurrent.futures.ThreadPoolExecutor(max_workers=2) as pool:
        replies = list(pool.map(lambda payment: request('POST', '/rest/v1/rpc/confirm_payment', tokens[0], {'p_payment_id': payment}), payments))
    statuses = sorted(response[0] for response in replies)
    check('Concurrent recipient confirmations cannot overpay', statuses == [200,400], statuses=statuses)
    status, balance = request('GET', route, tokens[1])
    check('One recipient confirmation settles exactly 600 centavos', status == 200 and int(balance) == 0, status=status)
    image = base64.b64decode('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+a8R8AAAAASUVORK5CYII=')
    media_route = '/storage/v1/object/profile-avatars/' + a + '/' + str(uuid.uuid4()) + '.png'
    status, _ = request('POST', media_route, tokens[0], data=image, extra={'Content-Type': 'image/png'})
    check('Owner uploads a private fixture image', status in [200,201], status=status)
    status, downloaded = request('GET', media_route, tokens[0])
    check('Owner reads matching image bytes', status == 200 and downloaded == image, status=status)
    status, _ = request('GET', media_route, tokens[2])
    check('Outsider cannot read the private image', status in [400,401,403,404], status=status)
    for worker in ['account-deletion','recurring-obligations','reminder-push']:
        status, _ = request('POST', '/functions/v1/' + worker, tokens[0], {})
        expected_status = 401 if worker == 'reminder-push' else 403
        check('Ordinary user denied ' + worker, status == expected_status, status=status)
    for table, original in baseline.items():
        if not original:
            continue
        identifiers = ','.join(literal(row['id']) + '::uuid' for row in original)
        after = json.loads(sql(f"SELECT coalesce(json_agg(t ORDER BY id),'[]') FROM public.{table} t WHERE id IN ({identifiers});"))
        check('Migrated original ' + table + ' rows unchanged', after == original, rows=len(original))
    report['outcome'] = 'passed'
except Exception as error:
    report['outcome'] = 'failed'
    report['failure'] = str(error) if isinstance(error, RuntimeError) else type(error).__name__
finally:
    (root / 'last-live-acceptance.json').write_text(json.dumps(report, indent=2))
    print(json.dumps(report), flush=True)
raise SystemExit(0 if report['outcome'] == 'passed' else 2)
