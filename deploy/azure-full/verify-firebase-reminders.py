"""Bounded live Google-recipient reminder acceptance; no scheduler activation.

The recipient uses actual Google/SDK authentication and UI consent. The tagged
synthetic sender invokes real RPCs under authenticated-role SQL fixture context;
that sender context is not claimed as a GoTrue-issued session or UI acceptance.
"""
import argparse
import datetime
import json
import os
import re
import secrets
import subprocess
import urllib.error
import urllib.request
import uuid
from pathlib import Path

ORIGIN = 'https://tabby-7abf436e-20261113.eastasia.cloudapp.azure.com'
RPCS = {'send_friend_request', 'create_group_v1', 'create_expense_v1', 'send_tab_reminder_v1'}


def literal(value):
    return "'" + str(value).replace("'", "''") + "'"


def checked_uuid(value):
    result = str(uuid.UUID(value))
    if result != value:
        raise ValueError('Canonical UUID required')
    return result


def actor_rpc_sql(actor, name, params):
    checked_uuid(actor)
    if name not in RPCS or not all(re.fullmatch(r'p_[a-z_]+', key) for key in params):
        raise ValueError('Only reviewed sender RPCs are allowed')
    values = []
    for key, value in params.items():
        suffix = '::jsonb' if isinstance(value, dict) else '::uuid' if key == 'p_operation_id' else '::text'
        values.append(key + '=>' + literal(json.dumps(value) if isinstance(value, dict) else value) + suffix)
    claims = literal(json.dumps({'sub': actor, 'role': 'authenticated'}))
    call = 'public.' + name + '(' + ','.join(values) + ')'
    select = "SELECT coalesce(jsonb_agg(to_jsonb(t)),'[]'::jsonb) FROM " + call + ' t' if name == 'send_friend_request' else 'SELECT to_jsonb(' + call + ')'
    return "BEGIN; DO $fixture$ BEGIN PERFORM set_config('request.jwt.claims'," + claims + ",true); END $fixture$; SET LOCAL ROLE authenticated; " + select + '; COMMIT;'


def dispatch_scope_allowed(counts):
    return counts == {'target_pending': 1, 'all_pending_or_sending': 1, 'other_active_bindings': 0}


def parse_psql(output):
    value = output.strip()
    if value in ('t', 'f'):
        return value == 't'
    return json.loads(value)


def queue_binding(state, requested):
    if requested is None:
        return checked_uuid(state['binding'])
    if state.get('phase') != 'await_recipient_acceptance' or state.get('expense') or state.get('notification'):
        raise ValueError('An already queued event cannot be rebound')
    return checked_uuid(requested)


def prepare_new_reminder(state, binding):
    if state.get('phase') != 'provider_accepted_await_native_delivery' or not state.get('expense'):
        raise ValueError('Previous reminder must be accepted before a new test event')
    checked_uuid(binding)
    history = {key: state[key] for key in ('notification', 'job', 'binding', 'reminder_operation')}
    state.setdefault('prior_events', []).append(history)
    state['binding'] = binding
    state['reminder_operation'] = str(uuid.uuid4())
    state.pop('notification', None)
    state.pop('job', None)
    state['phase'] = 'new_reminder_before_queue'


def main():
    os.umask(0o077)
    parser = argparse.ArgumentParser()
    parser.add_argument('action', choices=['prepare', 'queue', 'nudge', 'group', 'dispatch', 'retire'])
    parser.add_argument('--receiver')
    parser.add_argument('--binding')
    parser.add_argument('--run-id')
    args = parser.parse_args()
    root = Path('/srv/tabby/migration')
    if args.action == 'prepare':
        receiver, binding = checked_uuid(args.receiver), checked_uuid(args.binding)
        run_id = 'fcm-live-' + datetime.datetime.now(datetime.timezone.utc).strftime('%Y%m%dT%H%M%SZ') + '-' + secrets.token_hex(3)
        folder = root / run_id
        folder.mkdir(mode=0o700)
        state = {'run_id': run_id, 'receiver': receiver, 'binding': binding, 'checks': [], 'outcome': 'in_progress'}
    else:
        if not re.fullmatch(r'fcm-live-\d{8}T\d{6}Z-[a-f0-9]{6}', args.run_id or ''):
            raise ValueError('Approved acceptance run ID required')
        folder = root / args.run_id
        state = json.loads((folder / 'state.json').read_text())
        receiver, binding = checked_uuid(state['receiver']), checked_uuid(state['binding'])
        if args.action == 'queue':
            binding = queue_binding(state, args.binding)
            state['binding'] = binding
        elif args.action == 'nudge':
            binding = checked_uuid(args.binding)
            prepare_new_reminder(state, binding)
        elif args.action == 'group':
            binding = checked_uuid(args.binding)
            state['binding'] = binding
    env = dict(line.split('=', 1) for line in Path('/srv/tabby/.env').read_text().splitlines() if '=' in line and not line.startswith('#'))
    anon, service = (env[key].strip('"\'') for key in ('ANON_KEY', 'SERVICE_ROLE_KEY'))
    report = {'run_id': state['run_id'], 'action': args.action, 'outcome': 'failed', 'checks': [], 'private_account_ids_tokens_or_rows_logged': False, 'sender_authentication': 'tagged authenticated-role SQL fixture; not a real sender login', 'receiver_authentication': 'manual Google/actual app SDK', 'scheduler_enabled': False}

    def check(name, condition):
        report['checks'].append({'name': name, 'outcome': 'passed' if condition else 'failed'})
        if not condition:
            raise RuntimeError(name)

    def sql(query):
        answer = subprocess.run(['docker', 'exec', '-i', 'supabase-db', 'psql', '-X', '-qAt', '-U', 'supabase_admin', '-d', 'postgres', '-v', 'ON_ERROR_STOP=1'], input=query.encode(), capture_output=True, timeout=30)
        if answer.returncode:
            raise RuntimeError('Scoped database operation failed; private SQL output withheld')
        return parse_psql(answer.stdout.decode())

    def admin(method, route, body):
        request = urllib.request.Request(ORIGIN + '/auth/v1/admin/' + route, method=method, data=json.dumps(body).encode(), headers={'apikey': service, 'Authorization': 'Bearer ' + service, 'Content-Type': 'application/json'})
        with urllib.request.urlopen(request, timeout=30) as response:
            return json.load(response)

    def save():
        (folder / 'state.json').write_text(json.dumps(state))

    def fingerprints(tab=None):
        filters = {'transactions': '', 'payments': '', 'transaction_participants': '', 'payment_proofs': ''}
        if tab:
            tab = checked_uuid(tab)
            for table in ('transactions', 'payments'):
                filters[table] = ' WHERE t.tab_id IS DISTINCT FROM ' + literal(tab) + '::uuid'
            filters['transaction_participants'] = ' WHERE t.transaction_id NOT IN (SELECT id FROM public.transactions WHERE tab_id=' + literal(tab) + '::uuid)'
            filters['payment_proofs'] = ' WHERE t.payment_id NOT IN (SELECT id FROM public.payments WHERE tab_id=' + literal(tab) + '::uuid)'
        parts = [literal(table) + ",encode(sha256(convert_to(coalesce((SELECT jsonb_agg(to_jsonb(t) ORDER BY to_jsonb(t)::text) FROM public." + table + ' t' + where + "),'[]'::jsonb)::text,'UTF8')),'hex')" for table, where in filters.items()]
        return sql('BEGIN READ ONLY; SELECT jsonb_build_object(' + ','.join(parts) + '); ROLLBACK;')

    try:
        if args.action != 'retire':
            ready = sql("BEGIN READ ONLY; SELECT count(*)=1 FROM public.push_device_bindings d JOIN auth.users u ON u.id=d.user_id WHERE d.user_id=" + literal(receiver) + '::uuid AND d.binding_id=' + literal(binding) + "::uuid AND d.reminders_enabled AND d.expires_at>now() AND EXISTS(SELECT 1 FROM auth.identities i WHERE i.user_id=u.id AND i.provider='google') AND EXISTS(SELECT 1 FROM auth.sessions s WHERE s.user_id=u.id); ROLLBACK;")
            check('real_google_recipient_and_acknowledged_push_binding', ready is True)
        if args.action == 'prepare':
            state['before_financial_fingerprints'] = fingerprints()
            created = admin('POST', 'users', {'email': 'tabby-fcm-' + secrets.token_hex(12) + '@example.invalid', 'email_confirm': True, 'app_metadata': {'tabby_azure_fixture': True, 'tabby_fcm_run': state['run_id']}, 'user_metadata': {'display_name': 'Tabby QA Sender'}})
            state['sender'] = checked_uuid(created['id'])
            save()
        sender = checked_uuid(state['sender'])
        tagged = sql('BEGIN READ ONLY; SELECT count(*)=1 FROM auth.users WHERE id=' + literal(sender) + "::uuid AND raw_app_meta_data->>'tabby_azure_fixture'='true' AND raw_app_meta_data->>'tabby_fcm_run'=" + literal(state['run_id']) + '; ROLLBACK;')
        check('sender_has_exact_synthetic_run_tag', tagged is True and sender != receiver)
        if args.action == 'prepare':
            code = sql('BEGIN READ ONLY; SELECT to_jsonb(friend_code) FROM public.users WHERE id=' + literal(receiver) + '::uuid; ROLLBACK;')
            sent = sql(actor_rpc_sql(sender, 'send_friend_request', {'p_friend_code': code}))
            check('synthetic_sender_queues_one_friend_request', isinstance(sent, list) and len(sent) == 1)
            state['friendship'] = checked_uuid(sent[0]['id'])
            state['expense_operation'] = str(uuid.uuid4())
            state['reminder_operation'] = str(uuid.uuid4())
            state['phase'] = 'await_recipient_acceptance'
        elif args.action in ('queue', 'nudge', 'group'):
            pair = sql('BEGIN READ ONLY; SELECT coalesce(jsonb_agg(jsonb_build_object(\'status\',f.status,\'tab\',t.id)),\'[]\'::jsonb) FROM public.friendships f JOIN public.tabs t ON t.user_a=least(f.requester_id,f.addressee_id) AND t.user_b=greatest(f.requester_id,f.addressee_id) AND t.tab_type=\'individual\' WHERE f.id=' + literal(checked_uuid(state['friendship'])) + '::uuid; ROLLBACK;')
            check('recipient_explicitly_accepted_canonical_pair_in_app', len(pair) == 1 and pair[0]['status'] == 'accepted')
            if args.action == 'group' and not state.get('group_case'):
                # A separate genuine tab obeys the per-tab six-hour rule. Keep
                # every earlier test event/expense and never reset cooldowns.
                state.setdefault('prior_cases', []).append({key: state[key] for key in ('tab', 'expense', 'expense_operation', 'reminder_operation', 'before_financial_fingerprints') if key in state})
                state['before_financial_fingerprints'] = fingerprints()
                state['group_operation'] = str(uuid.uuid4())
                state['expense_operation'] = str(uuid.uuid4())
                state['reminder_operation'] = str(uuid.uuid4())
                state['group_case'] = True
                state.pop('expense', None)
                state.pop('notification', None)
                state.pop('job', None)
                save()
            if state.get('group_case'):
                group = sql(actor_rpc_sql(sender, 'create_group_v1', {'p_operation_id': state['group_operation'], 'p_command': {'name': 'Tabby QA notification check', 'member_user_ids': [receiver]}}))
                state['tab'] = checked_uuid(group['tab_id'])
                check('separate_group_created_only_with_accepted_test_friend', bool(group.get('group_id')))
            else:
                state['tab'] = checked_uuid(pair[0]['tab'])
            save()
            command = {'p_tab_id': state['tab'], 'p_description': 'Tabby QA reminder test', 'p_category': 'other', 'p_total_amount_centavos': 200, 'p_paid_by_user_id': sender, 'p_participants': [{'user_id': sender, 'participant_role': 'payer', 'share_amount_centavos': 100}, {'user_id': receiver, 'participant_role': 'debtor', 'share_amount_centavos': 100}], 'p_due_date': None, 'p_receipt_url': None}
            expense = sql(actor_rpc_sql(sender, 'create_expense_v1', {'p_operation_id': state['expense_operation'], 'p_command': command}))
            state['expense'] = checked_uuid(expense)
            check('integer_centavo_fixture_expense_created', bool(expense))
            reminder = sql(actor_rpc_sql(sender, 'send_tab_reminder_v1', {'p_operation_id': state['reminder_operation'], 'p_command': {'tab_id': state['tab'], 'recipient_user_id': receiver, 'title': 'Tabby QA reminder', 'body': 'Open the test tab to review this reminder.'}}))
            state['notification'] = checked_uuid(reminder)
            jobs = sql('BEGIN READ ONLY; SELECT coalesce(jsonb_agg(jsonb_build_object(\'id\',id,\'status\',status,\'binding_matches\',binding_id=' + literal(binding) + '::uuid)),\'[]\'::jsonb) FROM public.push_delivery_jobs WHERE notification_id=' + literal(reminder) + '::uuid; ROLLBACK;')
            check('real_notification_trigger_created_exact_pending_device_job', len(jobs) == 1 and jobs[0]['status'] == 'pending' and jobs[0]['binding_matches'])
            state['job'] = checked_uuid(jobs[0]['id'])
            state['phase'] = 'ready_for_manual_worker'
            check('all_preexisting_financial_rows_unchanged', fingerprints(state['tab']) == state['before_financial_fingerprints'])
        elif args.action == 'dispatch':
            job = checked_uuid(state['job'])
            counts = sql('BEGIN READ ONLY; SELECT jsonb_build_object(\'target_pending\',(SELECT count(*) FROM public.push_delivery_jobs WHERE id=' + literal(job) + '::uuid AND status=\'pending\'),\'all_pending_or_sending\',(SELECT count(*) FROM public.push_delivery_jobs WHERE status IN (\'pending\',\'sending\')),\'other_active_bindings\',(SELECT count(*) FROM public.push_device_bindings WHERE user_id<>' + literal(receiver) + '::uuid AND reminders_enabled AND expires_at>now())); ROLLBACK;')
            check('only_explicit_test_job_and_recipient_can_be_dispatched', dispatch_scope_allowed(counts))
            config = json.loads(Path('/srv/tabby/docker-compose.tabby.yml').read_text())
            secret = config['services']['functions']['environment']['PUSH_WORKER_SECRET']
            request = urllib.request.Request(ORIGIN + '/functions/v1/reminder-push', method='POST', data=b'{}', headers={'apikey': service, 'Authorization': 'Bearer ' + service, 'x-push-worker-secret': secret, 'Content-Type': 'application/json'})
            with urllib.request.urlopen(request, timeout=75) as response:
                totals = json.load(response)
            check('actual_gateway_worker_accepted_only_one_fixture_message', totals == {'accepted': 1, 'retry': 0, 'unregistered': 0, 'permanent': 0})
            accepted = sql('BEGIN READ ONLY; SELECT status=\'accepted\' AND attempts=1 AND lease_id IS NULL AND lease_until IS NULL FROM public.push_delivery_jobs WHERE id=' + literal(job) + '::uuid; ROLLBACK;')
            check('real_queue_lease_finished_as_provider_accepted', accepted is True)
            check('all_preexisting_financial_rows_unchanged', fingerprints(state['tab']) == state['before_financial_fingerprints'])
            state['phase'] = 'provider_accepted_await_native_delivery'
        else:
            retired = admin('PUT', 'users/' + sender, {'ban_duration': '876000h'})
            check('only_tagged_sender_access_retired', retired.get('id') == sender and bool(retired.get('banned_until')))
            check('all_preexisting_financial_rows_unchanged', fingerprints(state.get('tab')) == state['before_financial_fingerprints'])
            state['phase'] = 'sender_retired_recipient_preserved'
        report['outcome'] = 'passed'
    except Exception as error:
        report['error_type'] = type(error).__name__
    finally:
        state['checks'].extend(report['checks'])
        save()
        (folder / ('report-' + args.action + '.json')).write_text(json.dumps(report))
        print(json.dumps(report), flush=True)
    return 0 if report['outcome'] == 'passed' else 2


if __name__ == '__main__':
    raise SystemExit(main())
