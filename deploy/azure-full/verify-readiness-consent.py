"""Live Auth/HTTP consent checks using three newly tagged synthetic accounts.

Never deletes users, ledger rows or confirmed history. Synthetic identities are
retired after the check. Tokens/passwords and real record bodies are not logged.
"""
import concurrent.futures
import datetime
import importlib.util
import json
import os
import re
import secrets
import urllib.error
import urllib.request
from pathlib import Path


def main():
    os.umask(0o077)
    folder = Path(os.environ['TABBY_PATCH_FOLDER'])
    if folder.parent != Path('/srv/tabby/migration/readiness-patches') or not re.fullmatch(r'readiness-\d{8}T\d{6}Z-[a-f0-9]{8}', folder.name):
        raise ValueError('Approved patch folder required')
    committed = json.loads((folder / 'commit-report.json').read_text())
    if committed['outcome'] != 'passed':
        raise ValueError('Successful patch commit required')
    spec = importlib.util.spec_from_file_location('patch', folder / 'apply.py')
    patch = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(patch)
    env = {}
    for line in Path('/srv/tabby/.env').read_text().splitlines():
        if '=' in line and not line.startswith('#'):
            key, value = line.split('=', 1)
            env[key.strip()] = value.strip().strip('"').strip("'")
    # The app-facing Caddy origin is fixed to this approved migration target;
    # container environment URLs can name an internal upstream instead.
    origin = 'https://tabby-7abf436e-20261113.eastasia.cloudapp.azure.com'
    anon, service = env['ANON_KEY'], env['SERVICE_ROLE_KEY']
    report = {'run_id': folder.name, 'outcome': 'failed', 'checks': [], 'real_account_operations': False, 'financial_writes': False}
    attempt = datetime.datetime.now(datetime.timezone.utc).strftime('%Y%m%dT%H%M%SZ') + '-' + secrets.token_hex(3)
    report['attempt_id'] = attempt
    actors = []
    stage = 'catalog'

    def request(method, route, token, body=None, admin=False):
        data = None if body is None else json.dumps(body).encode()
        headers = {'apikey': service if admin else anon, 'Authorization': 'Bearer ' + token, 'Content-Type': 'application/json'}
        req = urllib.request.Request(origin + route, data=data, method=method, headers=headers)
        try:
            with urllib.request.urlopen(req, timeout=30) as response:
                raw = response.read(2 * 1024 * 1024)
                return response.status, json.loads(raw) if raw else None
        except urllib.error.HTTPError as error:
            raw = error.read(65536)
            return error.code, json.loads(raw) if raw else None

    def check(name, passed):
        report['checks'].append({'name': name, 'outcome': 'passed' if passed else 'failed'})
        if not passed:
            raise AssertionError(name)

    def rpc(actor, name, values):
        return request('POST', '/rest/v1/rpc/' + name, actor['token'], values)

    try:
        state = patch.psql("BEGIN READ ONLY; SELECT jsonb_build_object('migration_count',(SELECT count(*) FROM supabase_migrations.schema_migrations),'insert_granted',has_table_privilege('authenticated','public.friendships','INSERT'),'fingerprint'," + patch.snapshot_sql() + '); ROLLBACK;', folder)
        check('deployed52_and_insert_revoked', state['migration_count'] == 52 and not state['insert_granted'])
        check('history_matches_prepatch_backup_boundary', state['fingerprint'] == committed['database']['financial_fingerprints'])
        stage = 'tagged-auth-fixtures'
        for label in ('a', 'b', 'outsider'):
            password = secrets.token_urlsafe(42)
            email = 'readiness-' + attempt + '-' + label + '@example.invalid'
            status, created = request('POST', '/auth/v1/admin/users', service, {'email': email, 'password': password, 'email_confirm': True, 'app_metadata': {'tabby_azure_fixture': True, 'tabby_readiness_run': folder.name}, 'user_metadata': {'display_name': 'Readiness synthetic ' + label}}, admin=True)
            check('create_tagged_' + label, status in (200, 201) and bool(created.get('id')))
            actor = {'id': created['id'], 'email': email, 'password': password}
            actors.append(actor)
            (folder / ('synthetic-fixture-identities-' + attempt + '.json')).write_text(json.dumps([{'id': a['id'], 'run_id': folder.name} for a in actors]))
            status, auth = request('POST', '/auth/v1/token?grant_type=password', anon, {'email': email, 'password': password})
            check('auth_tag_verified_' + label, status == 200 and auth['user']['app_metadata'].get('tabby_readiness_run') == folder.name and auth['user']['app_metadata'].get('tabby_azure_fixture') is True)
            actor['token'] = auth['access_token']
            status, profile = request('GET', '/rest/v1/users?select=id,friend_code&id=eq.' + actor['id'], actor['token'])
            check('owned_profile_' + label, status == 200 and len(profile) == 1 and bool(profile[0].get('friend_code')))
            actor['code'] = profile[0]['friend_code']
        a, b, outsider = actors
        stage = 'consent-boundary'
        status, denied = request('POST', '/rest/v1/friendships', a['token'], {'id': None, 'requester_id': a['id'], 'addressee_id': b['id'], 'status': 'accepted'})
        check('direct_accepted_insert_denied', status in (401, 403) and denied.get('code') == '42501')
        status, rows = request('GET', '/rest/v1/users?select=id&id=eq.' + b['id'], a['token'])
        check('stranger_profile_hidden', status == 200 and rows == [])
        stage = 'opposing-concurrent-requests'
        with concurrent.futures.ThreadPoolExecutor(max_workers=2) as pool:
            futures = [pool.submit(rpc, a, 'send_friend_request', {'p_friend_code': b['code']}), pool.submit(rpc, b, 'send_friend_request', {'p_friend_code': a['code']})]
            replies = [f.result() for f in futures]
        report['request_reply_summary'] = [{'http_status': s, 'shape': type(data).__name__, 'sqlstate': data.get('code') if isinstance(data, dict) else None} for s, data in replies]
        # Opposing sends intentionally yield one request and one pending-inbound
        # notice. Only same-direction replay acknowledges the original identity.
        successes = [data for s, data in replies if s == 200 and isinstance(data, list) and len(data) == 1]
        notices = [data for s, data in replies if s >= 400 and isinstance(data, dict) and data.get('code') == 'P0001' and data.get('message') == 'This person has already sent you a request']
        check('opposing_requests_create_one_pending_and_one_inbound_notice', len(successes) == 1 and len(notices) == 1)
        check('opposing_requests_do_not_leak_unique_violation', all(not isinstance(data, dict) or data.get('code') != '23505' for _, data in replies))
        ids = a['id'] + ',' + b['id']
        query = '/rest/v1/friendships?select=id,status,requester_id,addressee_id&requester_id=in.(' + ids + ')&addressee_id=in.(' + ids + ')'
        status, rows = request('GET', query, a['token'])
        check('one_pending_pair_no_implicit_acceptance', status == 200 and len(rows) == 1 and rows[0]['status'] == 'pending')
        friendship = rows[0]
        requester = next(actor for actor in (a, b) if actor['id'] == friendship['requester_id'])
        recipient = next(actor for actor in (a, b) if actor['id'] == friendship['addressee_id'])
        status, replay = rpc(requester, 'send_friend_request', {'p_friend_code': recipient['code']})
        check('same_direction_replay_keeps_request_identity', status == 200 and isinstance(replay, list) and len(replay) == 1 and replay[0]['id'] == friendship['id'])
        params = {'p_friendship_id': friendship['id'], 'p_accept': True}
        status, _ = rpc(requester, 'respond_friend_request', params)
        check('requester_cannot_accept', status >= 400)
        status, _ = rpc(outsider, 'respond_friend_request', params)
        check('outsider_cannot_accept', status >= 400)
        stage = 'explicit-recipient-acceptance'
        status, accepted = rpc(recipient, 'respond_friend_request', params)
        check('recipient_accepts_and_gets_canonical_tab', status == 200 and accepted.get('status') == 'accepted' and bool(accepted.get('tab_id')))
        status, members = request('GET', '/rest/v1/tab_members?select=user_id&tab_id=eq.' + accepted['tab_id'], requester['token'])
        check('canonical_tab_has_exact_pair', status == 200 and {row['user_id'] for row in members} == {a['id'], b['id']})
        status, visible = request('GET', '/rest/v1/users?select=id&id=eq.' + b['id'], a['token'])
        check('accepted_friend_profile_visible', status == 200 and len(visible) == 1 and visible[0]['id'] == b['id'])
        status, hidden = request('GET', '/rest/v1/users?select=id&id=eq.' + b['id'], outsider['token'])
        check('outsider_profile_remains_hidden', status == 200 and hidden == [])
        after = patch.psql('BEGIN READ ONLY; SELECT jsonb_build_object(\'fingerprint\',' + patch.snapshot_sql() + '); ROLLBACK;', folder)
        check('existing_financial_history_unchanged', after['fingerprint'] == state['fingerprint'])
        report['outcome'] = 'passed'
    except Exception as error:
        report['stage'] = stage
        report['error_type'] = type(error).__name__
    finally:
        retired = 0
        for actor in actors:
            try:
                if actor.get('token'):
                    request('POST', '/auth/v1/logout?scope=global', actor['token'])
                status, _ = request('PUT', '/auth/v1/admin/users/' + actor['id'], service, {'ban_duration': '876000h'}, admin=True)
                login, _ = request('POST', '/auth/v1/token?grant_type=password', anon, {'email': actor['email'], 'password': actor['password']})
                if status == 200 and login >= 400:
                    retired += 1
            except Exception:
                pass
        report['tagged_fixture_accounts'] = len(actors)
        report['fixture_access_retired'] = retired == len(actors)
        if retired != len(actors):
            report['outcome'] = 'failed'
        report['checked_at'] = datetime.datetime.now(datetime.timezone.utc).isoformat()
        (folder / ('live-consent-report-' + attempt + '.json')).write_text(json.dumps(report))
        print(json.dumps(report), flush=True)
    return 0 if report['outcome'] == 'passed' else 2


if __name__ == '__main__':
    try:
        raise SystemExit(main())
    except Exception as error:
        print(json.dumps({'outcome': 'failed', 'stage': 'bootstrap', 'error_type': type(error).__name__}), flush=True)
        raise SystemExit(2)
