import assert from 'node:assert/strict';
import crypto from 'node:crypto';

// Permanent authenticated PostgREST regression journeys. The orchestration
// harness supplies only local loopback transport and disposable fixtures.
export async function runM1HttpRegressions({ apiAs, ids, addUsers, addIndividualTab, makeExpense, baseline }) {
  const evidence = {};
  const value = response => Array.isArray(response.body) ? response.body[0] : response.body;

  // QA-032: real PostgREST/RLS/command acceptance with local self-issued JWTs.
  // Auth-provider login and Realtime websocket delivery are separate evidence.
  for (const key of ['entryA', 'entryB', 'entryC', 'entryOutsider']) ids[key] = crypto.randomUUID();
  await addUsers(['entryA', 'entryB', 'entryC', 'entryOutsider']);
  const entryTab = await addIndividualTab('entry', 'entryA', 'entryB');
  const pairQuery = '/tabs?select=id&tab_type=eq.individual&or=' + encodeURIComponent(
    `(and(user_a.eq.${ids.entryA},user_b.eq.${ids.entryB}),and(user_a.eq.${ids.entryB},user_b.eq.${ids.entryA}))`);
  for (const actor of ['entryA', 'entryB']) {
    const existing = await apiAs(actor, 'GET', pairQuery);
    assert.equal(existing.status, 200);
    assert.deepEqual(existing.body.map(row => row.id), [entryTab]);
  }
  const before = await apiAs('entryA', 'GET', '/transactions?select=id&tab_id=eq.' + entryTab);
  assert.deepEqual(before.body, []); // selection and opposite-account reads wrote nothing
  const entryCommand = {p_tab_id: entryTab, p_description: 'Synthetic QA032 new loan',
    p_category: 'other', p_total_amount_centavos: 15000, p_paid_by_user_id: ids.entryA,
    p_participants: [{user_id: ids.entryA, participant_role: 'payer', share_amount_centavos: 0},
      {user_id: ids.entryB, participant_role: 'debtor', share_amount_centavos: 15000}],
    p_due_date: null, p_receipt_url: null};
  const operation = crypto.randomUUID();
  const submit = () => apiAs('entryA', 'POST', '/rpc/create_expense_v1',
    {p_operation_id: operation, p_command: entryCommand});
  await submit(); // deliberately lose the successful response
  const retries = await Promise.all(Array.from({length: 8}, submit));
  retries.forEach(row => assert.equal(row.status, 200, JSON.stringify(row)));
  const saved = value(retries[0]);
  assert(retries.every(row => value(row) === saved));
  const changed = await apiAs('entryA', 'POST', '/rpc/create_expense_v1',
    {p_operation_id: operation, p_command: {...entryCommand, p_description: 'Changed retry'}});
  assert.equal(changed.status, 400);
  const balanceOf = async (actor, tab) => {
    const response = await apiAs(actor, 'POST', '/rpc/get_tab_balances_v1', {p_tab_ids: [tab]});
    assert.equal(response.status, 200, JSON.stringify(response));
    return Number(response.body.balances.find(row => row.tab_id === tab).net_balance_centavos);
  };
  assert.equal(await balanceOf('entryA', entryTab), 15000);
  assert.equal(await balanceOf('entryB', entryTab), -15000);
  const secondLoan = await apiAs('entryA', 'POST', '/rpc/create_expense_v1',
    {p_operation_id: crypto.randomUUID(), p_command: entryCommand});
  assert.equal(secondLoan.status, 200);
  assert.notEqual(value(secondLoan), saved);
  for (const actor of ['entryA', 'entryB']) {
    const rows = await apiAs(actor, 'GET', '/transactions?select=id&tab_id=eq.' + entryTab);
    assert.equal(rows.status, 200);
    assert.equal(rows.body.length, 2);
  }
  assert.equal(await balanceOf('entryA', entryTab), 30000);
  assert.equal(await balanceOf('entryB', entryTab), -30000);
  const stranger = await apiAs('entryOutsider', 'GET', '/transactions?select=id&tab_id=eq.' + entryTab);
  assert.deepEqual(stranger.body, []);

  const customGroup = crypto.randomUUID();
  await baseline.query("INSERT INTO public.tabs(id,tab_type) VALUES ($1,'group')", [customGroup]);
  for (const key of ['entryA', 'entryB', 'entryC']) {
    await baseline.query('INSERT INTO public.tab_members(tab_id,user_id) VALUES ($1,$2)', [customGroup, ids[key]]);
  }
  const custom = {...entryCommand, p_tab_id: customGroup, p_total_amount_centavos: 45000,
    p_participants: [{user_id: ids.entryA, participant_role: 'payer', share_amount_centavos: 0},
      {user_id: ids.entryB, participant_role: 'debtor', share_amount_centavos: 15000},
      {user_id: ids.entryC, participant_role: 'debtor', share_amount_centavos: 30000}]};
  const customResult = await apiAs('entryA', 'POST', '/rpc/create_expense_v1',
    {p_operation_id: crypto.randomUUID(), p_command: custom});
  assert.equal(customResult.status, 200, JSON.stringify(customResult));
  for (const [actor, expected] of [['entryA', 45000], ['entryB', -15000], ['entryC', -30000]]) {
    assert.equal(await balanceOf(actor, customGroup), expected);
  }
  const malformed = await apiAs('entryA', 'POST', '/rpc/create_expense_v1',
    {p_operation_id: crypto.randomUUID(), p_command: {...custom, p_total_amount_centavos: 45001}});
  assert(malformed.status >= 400);
  evidence.qa032 = {pair_lookup_both_actors: true, selection_writes: 0,
    lost_response_parallel_retries: 8, replay_rows: 1, intentional_second_rows: 2,
    final_balances_centavos: [30000, -30000], custom_balances_centavos: [45000, -15000, -30000],
    sum_mismatch_denied: true, outsider_rows: 0,
    provenance: 'native PostgreSQL plus PostgREST; self-issued local JWT; no Google/GoTrue or Realtime assertion'};

  await addUsers(['permCapA', 'permCapB']);
  const capTab = await addIndividualTab('permCap', 'permCapA', 'permCapB');
  const capTotal = 800;
  const capOriginal = await makeExpense('permCapA', capTab, ids.permCapA, [
    {user_id: ids.permCapA, participant_role: 'payer', share_amount_centavos: 0},
    {user_id: ids.permCapB, participant_role: 'debtor', share_amount_centavos: capTotal},
  ], capTotal, 'Synthetic CAP-006 cancellation regression');
  const capRequest = await apiAs('permCapA', 'POST', '/rpc/request_expense_change_v2', {
    p_operation_id: crypto.randomUUID(), p_transaction_id: capOriginal, p_kind: 'cancel',
    p_new_total: null, p_reason: 'Permanent local cancellation regression',
    p_expected_actor: ids.permCapA, p_contact_agreement: false,
  });
  const capDecision = await apiAs('permCapB', 'POST', '/rpc/decide_expense_change_v1', {
    p_change_id: value(capRequest), p_accept: true, p_expected_actor: ids.permCapB,
  });
  const capRows = await apiAs('permCapA', 'GET',
    '/transactions?select=id,total_amount_centavos,status&id=eq.' + capOriginal);
  const capLogs = await apiAs('permCapA', 'GET',
    '/activity_logs?select=event_type,transaction_id,metadata&transaction_id=eq.' + capOriginal);
  const capOriginalRow = capRows.body.find(row => row.id === capOriginal);
  const capRevision = capLogs.body.find(row => row.event_type === 'EXPENSE_CHANGE_APPLIED');
  const capStatusLog = capLogs.body.find(row => row.event_type === 'DEBT_CANCELLED');
  assert.equal(capRequest.status, 200);
  assert.equal(capDecision.status, 200, JSON.stringify({request: capRequest, decision: capDecision}));
  assert.equal(capRows.status, 200);
  assert.equal(capRows.body.length, 1, 'cancellation must retain the original, not delete it');
  assert.equal(Number(capOriginalRow.total_amount_centavos), capTotal, 'cancellation must preserve original cents');
  assert.equal(capOriginalRow.status, 'cancelled');
  assert.equal(capRevision?.transaction_id, capOriginal);
  assert.equal(capRevision?.metadata.reason, 'Permanent local cancellation regression');
  assert.equal(capStatusLog?.metadata.total_amount_centavos, capTotal);
  evidence.cap006 = {request_status: capRequest.status, decision_status: capDecision.status,
    original_rows: capRows.body.length, original_total_centavos: Number(capOriginalRow.total_amount_centavos),
    original_status: capOriginalRow.status, revision_reason: capRevision.metadata.reason,
    status_audit_event: capStatusLog.event_type};

  await addUsers(['permHomeA', 'permHomeB']);
  const homeTab = await addIndividualTab('permHome', 'permHomeA', 'permHomeB');
  const homeExpense = await makeExpense('permHomeA', homeTab, ids.permHomeA, [
    {user_id: ids.permHomeA, participant_role: 'payer', share_amount_centavos: 0},
    {user_id: ids.permHomeB, participant_role: 'debtor', share_amount_centavos: 600},
  ], 600, 'Synthetic HOME-002 reminder regression');
  const reminderId = crypto.randomUUID();
  await baseline.query(`INSERT INTO public.reminders
    (id,created_by,recipient_user_id,transaction_id,reminder_type,scheduled_for,status)
    VALUES($1,$2,$3,$4,'overdue',now(),'scheduled')`,
  [reminderId, ids.permHomeA, ids.permHomeB, homeExpense]);
  const payment = await apiAs('permHomeB', 'POST', '/rpc/submit_payment_v1', {
    p_operation_id: crypto.randomUUID(), p_command: {p_tab_id: homeTab,
      p_submitted_by_user_id: ids.permHomeB, p_recipient_user_id: ids.permHomeA,
      p_amount_centavos: 600, p_payment_method: 'cash', p_note: 'Synthetic settle'},
  });
  const paymentId = value(payment);
  const confirmation = await apiAs('permHomeA', 'POST', '/rpc/confirm_payment', {p_payment_id: paymentId});
  const balance = await apiAs('permHomeB', 'GET',
    '/rpc/get_net_balance?p_tab_id=' + homeTab + '&p_user_id=' + ids.permHomeB);
  const reminders = await apiAs('permHomeB', 'GET',
    '/reminders?select=id,status,transaction_id&id=eq.' + reminderId);
  assert.equal(payment.status, 200);
  assert.equal(confirmation.status, 200);
  assert.equal(balance.status, 200);
  assert.equal(Number(value(balance)), 0);
  assert.equal(reminders.status, 200);
  assert.equal(reminders.body.length, 1, 'reminder history should remain after settlement');
  assert.equal(reminders.body[0].status, 'cancelled', 'settled reminder must not remain scheduled');
  evidence.home002 = {payment_status: payment.status, confirmation_status: confirmation.status,
    balance_centavos: Number(value(balance)), reminder_status: reminders.body[0].status,
    reminder_history_rows: reminders.body.length};

  await addUsers(['permNudgeA', 'permNudgeB']);
  const nudgeTab = await addIndividualTab('permNudge', 'permNudgeA', 'permNudgeB');
  await makeExpense('permNudgeA', nudgeTab, ids.permNudgeA, [
    {user_id: ids.permNudgeA, participant_role: 'payer', share_amount_centavos: 0},
    {user_id: ids.permNudgeB, participant_role: 'debtor', share_amount_centavos: 900},
  ], 900, 'Synthetic HOME-004 throttle regression');
  const command = {tab_id: nudgeTab, recipient_user_id: ids.permNudgeB,
    title: 'Synthetic reminder', body: 'Synthetic six-hour throttle'};
  const firstOp = crypto.randomUUID();
  const first = await apiAs('permNudgeA', 'POST', '/rpc/send_tab_reminder_v1',
    {p_operation_id: firstOp, p_command: command});
  const replay = await apiAs('permNudgeA', 'POST', '/rpc/send_tab_reminder_v1',
    {p_operation_id: firstOp, p_command: command});
  const replayConflict = await apiAs('permNudgeA', 'POST', '/rpc/send_tab_reminder_v1',
    {p_operation_id: firstOp, p_command: {...command, body: 'Changed payload'}});
  const immediate = await apiAs('permNudgeA', 'POST', '/rpc/send_tab_reminder_v1',
    {p_operation_id: crypto.randomUUID(), p_command: command});
  const nudgeRows = async () => apiAs('permNudgeB', 'GET',
    '/notifications?select=id,notification_type&related_tab_id=eq.' + nudgeTab + '&notification_type=eq.manual_nudge');
  assert.equal(first.status, 200);
  assert.equal(replay.status, 200);
  assert.equal(value(replay), value(first));
  assert.equal(replayConflict.status, 400);
  assert.equal(immediate.status, 429);
  assert.equal(immediate.body.code, 'PT429');
  assert.equal(immediate.body.message, 'Reminder rate limit exceeded');
  let rows = await nudgeRows();
  assert.equal(rows.status, 200);
  assert.equal(rows.body.length, 1, 'throttled request must not commit another notification');
  await baseline.query(`UPDATE public.reminder_operations SET accepted_at=now()-interval '5 hours 59 minutes'
    WHERE actor_id=$1 AND operation_id=$2`, [ids.permNudgeA, firstOp]);
  const beforeWindow = await apiAs('permNudgeA', 'POST', '/rpc/send_tab_reminder_v1',
    {p_operation_id: crypto.randomUUID(), p_command: command});
  assert.equal(beforeWindow.status, 429, 'still throttled before six hours');
  await baseline.query(`UPDATE public.reminder_operations SET accepted_at=now()-interval '6 hours 1 second'
    WHERE actor_id=$1 AND operation_id=$2`, [ids.permNudgeA, firstOp]);
  const afterWindow = await apiAs('permNudgeA', 'POST', '/rpc/send_tab_reminder_v1',
    {p_operation_id: crypto.randomUUID(), p_command: command});
  assert.equal(afterWindow.status, 200, 'new reminder is allowed after six hours');
  rows = await nudgeRows();
  assert.equal(rows.body.length, 2);

  await addUsers(['permRaceA', 'permRaceB']);
  const raceTab = await addIndividualTab('permRace', 'permRaceA', 'permRaceB');
  await makeExpense('permRaceA', raceTab, ids.permRaceA, [
    {user_id: ids.permRaceA, participant_role: 'payer', share_amount_centavos: 0},
    {user_id: ids.permRaceB, participant_role: 'debtor', share_amount_centavos: 700},
  ], 700, 'Synthetic HOME-004 concurrent double-tap regression');
  const concurrent = await Promise.all([1, 2].map(() => apiAs('permRaceA', 'POST', '/rpc/send_tab_reminder_v1', {
    p_operation_id: crypto.randomUUID(), p_command: {tab_id: raceTab,
      recipient_user_id: ids.permRaceB, title: 'Concurrent reminder', body: 'Only one should commit'},
  })));
  const raceRows = await apiAs('permRaceB', 'GET',
    '/notifications?select=id,notification_type&related_tab_id=eq.' + raceTab + '&notification_type=eq.manual_nudge');
  assert.deepEqual(concurrent.map(response => response.status).sort(), [200, 429]);
  assert.equal(concurrent.find(response => response.status === 429).body.code, 'PT429');
  assert.equal(raceRows.body.length, 1, 'concurrent distinct operation IDs must commit one nudge');
  evidence.home004 = {first_status: first.status, replay_status: replay.status,
    changed_payload_status: replayConflict.status, immediate_throttle_status: immediate.status,
    throttle_sqlstate: immediate.body.code, rows_after_throttle: 1,
    at_5h59m_status: beforeWindow.status, at_6h1s_status: afterWindow.status,
    rows_after_window: rows.body.length, concurrent_statuses: concurrent.map(response => response.status),
    concurrent_committed_notifications: raceRows.body.length};
  return evidence;
}

// Remaining authenticated group/payment/privacy journeys. These run against
// the same disposable local PostgREST instance as the M1 regression suite.
export async function runGroupPrivacyHttpRegressions({
  apiAs, apiAsWithClaims, apiService, ids, addUsers, addIndividualTab,
  makeExpense, baseline,
}) {
  const assertions = [];
  const results = {};
  const check = (name, passed, expected, actual) => {
    assertions.push({name, passed: !!passed, expected, actual});
  };
  const value = response => Array.isArray(response.body) ? response.body[0] : response.body;
  const jsonRows = response => Array.isArray(response.body) ? response.body : [];
  const balance = async (actor, tab, user) => apiAs(actor, 'GET',
    `/rpc/get_net_balance?p_tab_id=${tab}&p_user_id=${user}`);
  const addGroupMembers = async (tab, members) => {
    await baseline.query("INSERT INTO public.tabs(id,tab_type,status) VALUES($1,'group','active')", [tab]);
    await baseline.query('INSERT INTO public.tab_members(tab_id,user_id) SELECT $1,x::uuid FROM unnest($2::text[]) x',
      [tab, members.map(x => ids[x])]);
  };

  // GRP-001: actual B-to-C group settlement cannot alter uninvolved A.
  await addUsers(['grp1A', 'grp1B', 'grp1C']);
  const g1 = crypto.randomUUID();
  await addGroupMembers(g1, ['grp1A', 'grp1B', 'grp1C']);
  await makeExpense('grp1C', g1, ids.grp1C, [
    {user_id: ids.grp1A, participant_role: 'debtor', share_amount_centavos: 3000},
    {user_id: ids.grp1B, participant_role: 'debtor', share_amount_centavos: 3000},
    {user_id: ids.grp1C, participant_role: 'payer', share_amount_centavos: 4000},
  ], 10000, 'Synthetic GRP-001 isolated group payment');
  const aBefore = await balance('grp1A', g1, ids.grp1A);
  const submit = await apiAs('grp1B', 'POST', '/rpc/submit_payment_v1', {
    p_operation_id: crypto.randomUUID(), p_command: {p_tab_id: g1,
      p_submitted_by_user_id: ids.grp1B, p_recipient_user_id: ids.grp1C,
      p_amount_centavos: 1000, p_payment_method: 'cash', p_note: 'Synthetic group pair payment'},
  });
  const paymentId = value(submit);
  const confirm = await apiAs('grp1C', 'POST', '/rpc/confirm_payment', {p_payment_id: paymentId});
  const aAfter = await balance('grp1A', g1, ids.grp1A);
  const g1Rows = await apiAs('grp1A', 'GET', `/payments?select=id,status,amount_centavos&tab_id=eq.${g1}`);
  const a0 = Number(value(aBefore)), a1 = Number(value(aAfter));
  check('GRP-001 uninvolved group member balance', submit.status === 200 && confirm.status === 200 && a0 === a1,
    {http: [200, 200], uninvolved_balance_unchanged: true},
    {submit: submit.status, confirm: confirm.status, before: a0, after: a1,
      payment_rows: jsonRows(g1Rows).length});
  results.grp001 = {submit_status: submit.status, confirm_status: confirm.status,
    uninvolved_balance_before: a0, uninvolved_balance_after: a1, payment_rows: jsonRows(g1Rows).length};

  // GRP-002: exact per-person shares include separately rounded tax and service.
  await addUsers(['grp2A', 'grp2B', 'grp2C']);
  // Base 1001, tax 100 (10%), service 50 (5%). Deterministic remainder
  // allocation yields final shares 383, 382, 386 centavos respectively.
  const shares = new Map([[ids.grp2A, 383], [ids.grp2B, 382], [ids.grp2C, 386]]);
  const payerResults = [];
  for (const payer of ['grp2A', 'grp2B', 'grp2C']) {
    const payerTab = crypto.randomUUID();
    await addGroupMembers(payerTab, ['grp2A', 'grp2B', 'grp2C']);
    const expense = await makeExpense(payer, payerTab, ids[payer], ['grp2A', 'grp2B', 'grp2C'].map(user => ({
      user_id: ids[user], participant_role: user === payer ? 'payer' : 'debtor',
      share_amount_centavos: shares.get(ids[user]),
    })), 1151, `Synthetic GRP-002 payer ${payer}`);
    const rows = await apiAs(payer, 'GET', `/transaction_participants?select=user_id,participant_role,share_amount_centavos&transaction_id=eq.${expense}`);
    const actual = new Map(jsonRows(rows).map(row => [row.user_id, {
      role: row.participant_role, cents: Number(row.share_amount_centavos),
    }]));
    const sums = [...actual.values()].reduce((n, row) => n + row.cents, 0);
    const actualPayer = [...actual].find(([, row]) => row.role === 'payer')?.[0];
    const balances = await Promise.all(['grp2A', 'grp2B', 'grp2C'].map(async user => {
      const response = await balance(user, payerTab, ids[user]);
      return {user: ids[user], status: response.status, cents: Number(value(response))};
    }));
    const expectedBalances = ['grp2A', 'grp2B', 'grp2C'].map(user =>
      user === payer ? 1151 - shares.get(ids[user]) : -shares.get(ids[user]));
    const passed = rows.status === 200 && actual.size === 3 && sums === 1151 && actualPayer === ids[payer] &&
      ['grp2A', 'grp2B', 'grp2C'].every(user => actual.get(ids[user])?.cents === shares.get(ids[user])) &&
      balances.every((row, i) => row.status === 200 && row.cents === expectedBalances[i]);
    payerResults.push({payer: ids[payer], tab_id: payerTab, expense_id: expense, participant_status: rows.status,
      participant_rows: jsonRows(rows), share_sum_centavos: sums, balances});
    check(`GRP-002 all shares and payer selection ${payer}`, passed,
      {participant_count: 3, share_sum_centavos: 1151, tax_centavos: 100,
        service_centavos: 50, selected_payer: ids[payer]},
      {participant_status: rows.status, participants: jsonRows(rows), share_sum_centavos: sums,
        selected_payer: actualPayer, balances});
  }
  results.grp002 = {base_centavos: 1001, tax_basis_points: 1000, tax_centavos: 100,
    service_basis_points: 500, service_centavos: 50, final_total_centavos: 1151, payer_runs: payerResults};

  // GRP-003: group UUID is rejected as both settlement sides; no payment row.
  await addUsers(['grp3A', 'grp3B', 'grp3C']);
  const g3 = crypto.randomUUID(), groupId = crypto.randomUUID();
  await baseline.query("INSERT INTO public.groups(id,created_by,name) VALUES($1,$2,'Synthetic GRP-003')",
    [groupId, ids.grp3A]);
  await baseline.query("INSERT INTO public.group_members(group_id,user_id,role,status) VALUES($1,$2,'admin','active'),($1,$3,'member','active'),($1,$4,'member','active')",
    [groupId, ids.grp3A, ids.grp3B, ids.grp3C]);
  await baseline.query("INSERT INTO public.tabs(id,tab_type,status,group_id) VALUES($1,'group','active',$2)", [g3, groupId]);
  await baseline.query('INSERT INTO public.tab_members(tab_id,user_id) SELECT $1,x::uuid FROM unnest($2::text[]) x',
    [g3, ['grp3A', 'grp3B', 'grp3C'].map(x => ids[x])]);
  await makeExpense('grp3C', g3, ids.grp3C, [
    {user_id: ids.grp3A, participant_role: 'debtor', share_amount_centavos: 0},
    {user_id: ids.grp3B, participant_role: 'debtor', share_amount_centavos: 500},
    {user_id: ids.grp3C, participant_role: 'payer', share_amount_centavos: 500},
  ], 1000, 'Synthetic GRP-003 person-only settlement');
  const groupPayee = await apiAs('grp3B', 'POST', '/rpc/submit_payment_v1', {
    p_operation_id: crypto.randomUUID(), p_command: {p_tab_id: g3,
      p_submitted_by_user_id: ids.grp3B, p_recipient_user_id: groupId,
      p_amount_centavos: 100, p_payment_method: 'cash', p_note: null},
  });
  const groupPayer = await apiAs('grp3B', 'POST', '/rpc/submit_payment_v1', {
    p_operation_id: crypto.randomUUID(), p_command: {p_tab_id: g3,
      p_submitted_by_user_id: groupId, p_recipient_user_id: ids.grp3C,
      p_amount_centavos: 100, p_payment_method: 'cash', p_note: null},
  });
  const g3Rows = await apiAs('grp3B', 'GET', `/payments?select=id,status&tab_id=eq.${g3}`);
  check('GRP-003 group cannot be payer or payee', groupPayee.status >= 400 && groupPayer.status >= 400 && jsonRows(g3Rows).length === 0,
    {both_http_rejected: true, payment_rows: 0},
    {group_as_payee_status: groupPayee.status, group_as_payer_status: groupPayer.status,
      group_payee_error: groupPayee.body, group_payer_error: groupPayer.body, payment_rows: jsonRows(g3Rows).length});
  results.grp003 = {group_as_payee_status: groupPayee.status, group_as_payer_status: groupPayer.status,
    committed_payment_rows: jsonRows(g3Rows).length};

  // GRP-004: fail in the member-insert stage over HTTP, then retry same ID.
  await addUsers(['grp4A', 'grp4B']);
  await baseline.query("INSERT INTO public.friendships(requester_id,addressee_id,status) VALUES($1,$2,'accepted')",
    [ids.grp4A, ids.grp4B]);
  const counts = async () => {
    const names = ['groups', 'group_members', 'tabs', 'tab_members', 'group_creation_commands'];
    const rows = {};
    for (const name of names) rows[name] = Number((await baseline.query(`SELECT count(*)::int AS n FROM public.${name}`)).rows[0].n);
    return rows;
  };
  const before = await counts(), op = crypto.randomUUID();
  await baseline.query("CREATE FUNCTION public.qa_fail_group_member_insert() RETURNS trigger LANGUAGE plpgsql AS $$ BEGIN RAISE EXCEPTION 'Synthetic member insert failure' USING ERRCODE='P0001'; END $$");
  await baseline.query('CREATE TRIGGER qa_fail_group_member_insert BEFORE INSERT ON public.group_members FOR EACH ROW EXECUTE FUNCTION public.qa_fail_group_member_insert()');
  const failedCreate = await apiAs('grp4A', 'POST', '/rpc/create_group_v1', {
    p_operation_id: op, p_command: {name: 'Synthetic atomic failure', member_user_ids: [ids.grp4B]},
  });
  const afterFailure = await counts();
  await baseline.query('DROP TRIGGER qa_fail_group_member_insert ON public.group_members; DROP FUNCTION public.qa_fail_group_member_insert()');
  const retry = await apiAs('grp4A', 'POST', '/rpc/create_group_v1', {
    p_operation_id: op, p_command: {name: 'Synthetic atomic failure', member_user_ids: [ids.grp4B]},
  });
  const replay = await apiAs('grp4A', 'POST', '/rpc/create_group_v1', {
    p_operation_id: op, p_command: {name: 'Synthetic atomic failure', member_user_ids: [ids.grp4B]},
  });
  const afterRetry = await counts();
  const expectedAfterRetry = Object.fromEntries(Object.keys(before).map(name =>
    [name, before[name] + (name === 'group_members' || name === 'tab_members' ? 2 : 1)]));
  const retryId = value(retry)?.group_id;
  check('GRP-004 member-insert fault rolls back, retry creates one complete group',
    failedCreate.status >= 400 && JSON.stringify(afterFailure) === JSON.stringify(before) &&
      retry.status === 200 && replay.status === 200 && value(replay)?.group_id === retryId &&
      JSON.stringify(afterRetry) === JSON.stringify(expectedAfterRetry),
    {failed_request_no_rows: true, retry_status: 200, complete_group_once: true},
    {failure_status: failedCreate.status, failure_body: failedCreate.body, before, after_failure: afterFailure,
      retry_status: retry.status, replay_status: replay.status, retry_id: retryId,
      replay_id: value(replay)?.group_id, after_retry: afterRetry});
  results.grp004 = {failure_status: failedCreate.status, failure_body: failedCreate.body,
    before, after_failure: afterFailure, retry_status: retry.status, replay_status: replay.status,
    group_id: retryId, after_retry: afterRetry};

  // GRP-005: every client-facing M1 currency RPC returns the same stable,
  // actionable error and commits nothing for malformed integer-centavo input.
  await addUsers(['grp5A', 'grp5B']);
  const g5 = await addIndividualTab('grp5', 'grp5A', 'grp5B');
  const beforeRows = await apiAs('grp5A', 'GET', `/transactions?select=id&tab_id=eq.${g5}`);
  const malformed = await apiAs('grp5A', 'POST', '/rpc/create_expense_v1', {
    p_operation_id: crypto.randomUUID(), p_command: {p_tab_id: g5, p_description: 'Synthetic malformed PHP',
      p_category: 'other', p_total_amount_centavos: 'abc.50', p_paid_by_user_id: ids.grp5A,
      p_participants: [{user_id: ids.grp5A, participant_role: 'payer', share_amount_centavos: 0},
        {user_id: ids.grp5B, participant_role: 'debtor', share_amount_centavos: 'abc.50'}],
      p_due_date: null, p_receipt_url: null},
  });
  const malformedPayment = await apiAs('grp5B', 'POST', '/rpc/submit_payment_v1', {
    p_operation_id: crypto.randomUUID(), p_command: {p_tab_id: g5,
      p_submitted_by_user_id: ids.grp5B, p_recipient_user_id: ids.grp5A,
      p_amount_centavos: '1.234', p_payment_method: 'cash', p_note: null},
  });
  const malformedPaymentV2 = await apiAs('grp5B', 'POST', '/rpc/submit_payment_v2', {
    p_operation_id: crypto.randomUUID(), p_command: {p_tab_id: g5,
      p_submitted_by_user_id: ids.grp5B, p_recipient_user_id: ids.grp5A,
      p_amount_centavos: '999999999999999999999999', p_payment_method: 'cash', p_note: null},
  });
  const cashContactId = crypto.randomUUID(), cashContactTab = crypto.randomUUID();
  await baseline.query("INSERT INTO public.contacts(id,owner_user_id,display_name,claim_status) VALUES($1,$2,'Synthetic cash contact','unclaimed')",
    [cashContactId, ids.grp5A]);
  await baseline.query('INSERT INTO public.tabs(id,user_a) VALUES($1,$2)', [cashContactTab, ids.grp5A]);
  await baseline.query('INSERT INTO public.tab_members(tab_id,user_id) VALUES($1,$2)', [cashContactTab, ids.grp5A]);
  await baseline.query('INSERT INTO public.tab_members(tab_id,contact_id) VALUES($1,$2)', [cashContactTab, cashContactId]);
  const malformedReceived = await apiAs('grp5A', 'POST', '/rpc/record_received_payment_v1', {
    p_operation_id: crypto.randomUUID(), p_command: {p_tab_id: cashContactTab,
      payer: {kind: 'contact', id: cashContactId}, recipient: {kind: 'user', id: ids.grp5A},
      amount_centavos: '2e3', method: 'cash', note: null},
  });
  const afterRows = await apiAs('grp5A', 'GET', `/transactions?select=id&tab_id=eq.${g5}`);
  const currencyResponses = [malformed, malformedPayment, malformedPaymentV2, malformedReceived];
  const expectedMessage = 'Invalid financial input. Enter amounts as whole centavos and check the submitted values.';
  const normalized = currencyResponses.every(response => response.status === 400 &&
    response.body?.code === 'PT400' && response.body?.message === expectedMessage &&
    !response.body?.details && !response.body?.hint &&
    !/22P02|22003|bigint|invalid input syntax|PL\/pgSQL|constraint/i.test(JSON.stringify(response.body)));
  const noExpenseRows = jsonRows(beforeRows).length === jsonRows(afterRows).length;
  const noPaymentRows = async () => {
    const rows = await apiAs('grp5B', 'GET', `/payments?select=id&tab_id=eq.${g5}`);
    return jsonRows(rows);
  };
  const committedPayments = await noPaymentRows();
  check('GRP-005 all M1 malformed-currency RPCs return stable PT400 and commit no row', normalized &&
    noExpenseRows && committedPayments.length === 0,
    {http_status: 400, error_code: 'PT400', no_database_details: true, committed_expense_rows: 0,
      committed_payment_rows: 0},
    {responses: currencyResponses.map(response => ({status: response.status, body: response.body})),
      rows_before: jsonRows(beforeRows).length, rows_after: jsonRows(afterRows).length,
      committed_payment_rows: committedPayments.length});
  results.grp005 = {responses: currencyResponses.map(response => ({http_status: response.status, body: response.body})),
    normalized_error_shape: normalized, committed_expense_rows_before: jsonRows(beforeRows).length,
    committed_expense_rows_after: jsonRows(afterRows).length, committed_payment_rows: committedPayments.length};

  // PAY-001: confirmation changes the submitted row, never inserts another.
  await addUsers(['pay001A', 'pay001B']);
  const payTab = await addIndividualTab('pay001', 'pay001A', 'pay001B');
  await makeExpense('pay001A', payTab, ids.pay001A, [
    {user_id: ids.pay001A, participant_role: 'payer', share_amount_centavos: 0},
    {user_id: ids.pay001B, participant_role: 'debtor', share_amount_centavos: 500},
  ], 500, 'Synthetic PAY-001 duplicate confirmation');
  const submitted = await apiAs('pay001B', 'POST', '/rpc/submit_payment_v1', {
    p_operation_id: crypto.randomUUID(), p_command: {p_tab_id: payTab,
      p_submitted_by_user_id: ids.pay001B, p_recipient_user_id: ids.pay001A,
      p_amount_centavos: 500, p_payment_method: 'cash', p_note: null},
  });
  const originalPaymentId = value(submitted);
  const firstDecision = await apiAs('pay001A', 'POST', '/rpc/confirm_payment', {p_payment_id: originalPaymentId});
  const duplicateDecision = await apiAs('pay001A', 'POST', '/rpc/confirm_payment', {p_payment_id: originalPaymentId});
  const paymentRows = await apiAs('pay001A', 'GET', `/payments?select=id,status,amount_centavos&tab_id=eq.${payTab}`);
  check('PAY-001 confirming payment does not add a second payment row', submitted.status === 200 &&
    firstDecision.status === 200 && duplicateDecision.status < 500 && jsonRows(paymentRows).length === 1 &&
    jsonRows(paymentRows)[0]?.id === originalPaymentId && jsonRows(paymentRows)[0]?.status === 'confirmed',
    {one_original_payment_row: true, status: 'confirmed'},
    {submit_status: submitted.status, first_confirmation_status: firstDecision.status,
      repeat_confirmation_status: duplicateDecision.status, rows: jsonRows(paymentRows)});
  results.pay001 = {submit_status: submitted.status, first_confirmation_status: firstDecision.status,
    repeat_confirmation_status: duplicateDecision.status, committed_rows: jsonRows(paymentRows)};

  // SEC-005: caller-scoped export, recent-auth deletion request and reviewed
  // local processing, then inspect what the former counterpart still reads.
  await addUsers(['sec5A', 'sec5B']);
  const secTab = await addIndividualTab('sec5', 'sec5A', 'sec5B');
  const secExpense = await makeExpense('sec5A', secTab, ids.sec5A, [
    {user_id: ids.sec5A, participant_role: 'payer', share_amount_centavos: 0},
    {user_id: ids.sec5B, participant_role: 'debtor', share_amount_centavos: 1200},
  ], 1200, 'Synthetic SEC-005 shared history retained');
  const secPayment = await apiAs('sec5B', 'POST', '/rpc/submit_payment_v1', {
    p_operation_id: crypto.randomUUID(), p_command: {p_tab_id: secTab,
      p_submitted_by_user_id: ids.sec5B, p_recipient_user_id: ids.sec5A,
      p_amount_centavos: 200, p_payment_method: 'cash', p_note: 'Shared payment retained'},
  });
  const secPaymentId = value(secPayment);
  const secConfirm = await apiAs('sec5A', 'POST', '/rpc/confirm_payment', {p_payment_id: secPaymentId});
  const contactId = crypto.randomUUID();
  await baseline.query("INSERT INTO public.contacts(id,owner_user_id,display_name,email,claim_status) VALUES($1,$2,'Synthetic private contact','private@example.invalid','unclaimed')",
    [contactId, ids.sec5A]);
  const exportA = await apiAs('sec5A', 'POST', '/rpc/export_account_data_v1', {});
  const exportB = await apiAs('sec5B', 'POST', '/rpc/export_account_data_v1', {});
  const exportValueA = value(exportA), exportValueB = value(exportB);
  // Model a profile with fields that must be scrubbed, using only synthetic data.
  const syntheticAuthEmail = (await baseline.query(
    'SELECT email FROM auth.users WHERE id = $1', [ids.sec5A])).rows[0]?.email;
  const avatarPath = `${ids.sec5A}/${crypto.randomUUID()}.png`;
  await baseline.query(`INSERT INTO storage.objects(bucket_id, name, owner_id, owner)
    VALUES ('profile-avatars', $1, $2::text, $2::uuid)`, [avatarPath, ids.sec5A]);
  await baseline.query(`UPDATE public.users
    SET email = $1, phone = $2, avatar_url = $3
    WHERE id = $4`,
  [syntheticAuthEmail, '+639000000005', `avatar:${avatarPath}`, ids.sec5A]);
  const profileBeforeSeed = await baseline.query(
    'SELECT display_name, email, phone, avatar_url FROM public.users WHERE id = $1', [ids.sec5A]);
  const counterpartProfileBefore = await apiAs('sec5B', 'GET',
    `/users?select=id,display_name,email,phone,avatar_url&id=eq.${ids.sec5A}`);
  const deletion = await apiAsWithClaims('sec5A', 'POST', '/rpc/request_account_deletion_v1', {}, {
    amr: [{method: 'password', timestamp: Math.floor(Date.now() / 1000)}],
  });
  const deletionId = value(deletion)?.id;
  const requestAsOwner = await apiAs('sec5A', 'GET', `/account_deletion_requests?select=id,status&user_id=eq.${ids.sec5A}`);
  const requestAsCounterpart = await apiAs('sec5B', 'GET', `/account_deletion_requests?select=id,status&user_id=eq.${ids.sec5A}`);
  const review = await apiService('POST', '/rpc/review_account_deletion_v1', {p_request_id: deletionId});
  const prepare = await apiService('POST', '/rpc/prepare_account_deletion_v1', {p_request_id: deletionId});
  const pendingObjects = await apiService('POST', '/rpc/pending_deletion_objects_v1', {p_request_id: deletionId});
  // The local harness substitutes direct object removal for Supabase Storage.
  const objectAcks = [];
  for (const object of jsonRows(pendingObjects)) {
    await baseline.query('DELETE FROM storage.objects WHERE bucket_id = $1 AND name = $2',
      [object.bucket, object.path]);
    objectAcks.push(await apiService('POST', '/rpc/acknowledge_deletion_object_v1', {
      p_request_id: deletionId, p_bucket: object.bucket, p_path: object.path,
    }));
  }
  // The local Auth fixture simulates the separate Auth Admin soft-delete step;
  // it is not an Auth-issued or GoTrue acceptance claim.
  await baseline.query('UPDATE auth.users SET deleted_at=now() WHERE id=$1', [ids.sec5A]);
  await baseline.query('DELETE FROM auth.sessions WHERE user_id=$1', [ids.sec5A]);
  const finish = await apiService('POST', '/rpc/finish_account_deletion_v1', {p_request_id: deletionId});
  const ownerAfter = await apiAs('sec5A', 'GET', `/transactions?select=id,total_amount_centavos&id=eq.${secExpense}`);
  const formerCounterpartExpense = await apiAs('sec5B', 'GET', `/transactions?select=id,total_amount_centavos,status&id=eq.${secExpense}`);
  const formerCounterpartPayment = await apiAs('sec5B', 'GET', `/payments?select=id,status,amount_centavos&id=eq.${secPaymentId}`);
  const counterpartProfile = await apiAs('sec5B', 'GET',
    `/users?select=id,display_name,email,phone,avatar_url&id=eq.${ids.sec5A}`);
  const finalRequest = await apiAs('sec5B', 'GET', `/account_deletion_requests?select=id,status&user_id=eq.${ids.sec5A}`);
  const actualOwnerContact = (exportValueA?.contacts || []).some(row => row.id === contactId);
  const otherExportLeaksContact = JSON.stringify(exportValueB).includes('private@example.invalid');
  const formerRows = jsonRows(formerCounterpartExpense), formerPayments = jsonRows(formerCounterpartPayment);
  const profileAfter = jsonRows(counterpartProfile)[0];
  const profileBefore = profileBeforeSeed.rows[0];
  const syntheticPiiSeeded = typeof profileBefore?.display_name === 'string' &&
    profileBefore?.email === syntheticAuthEmail && profileBefore?.phone === '+639000000005' &&
    profileBefore?.avatar_url === `avatar:${avatarPath}`;
  const identityRedactedAfter = profileAfter?.display_name === 'Former member' &&
    profileAfter?.email === null && profileAfter?.phone === null && profileAfter?.avatar_url === null;
  check('SEC-005 export is subject-scoped and contains no counterpart contact',
    exportA.status === 200 && exportB.status === 200 && exportValueA?.account_id === ids.sec5A &&
      exportValueB?.account_id === ids.sec5B && actualOwnerContact && !otherExportLeaksContact,
    {owner_export_scoped: true, counterpart_private_contact_absent: true},
    {owner_export_status: exportA.status, counterpart_export_status: exportB.status,
      owner_account_id: exportValueA?.account_id, counterpart_account_id: exportValueB?.account_id,
      owner_contact_present: actualOwnerContact, counterpart_leaks_owner_contact: otherExportLeaksContact});
  check('SEC-005 deletion request/review completes while former counterpart retains shared records',
    secPayment.status === 200 && secConfirm.status === 200 && deletion.status === 200 && deletionId &&
      counterpartProfileBefore.status === 200 && syntheticPiiSeeded && counterpartProfile.status === 200 &&
      jsonRows(counterpartProfile).length === 1 && identityRedactedAfter &&
      requestAsOwner.status === 200 && jsonRows(requestAsOwner).length === 1 &&
      requestAsCounterpart.status === 200 && jsonRows(requestAsCounterpart).length === 0 &&
      review.status === 200 && prepare.status === 200 && pendingObjects.status === 200 &&
      objectAcks.length === jsonRows(pendingObjects).length && objectAcks.every(x => x.status === 200) &&
      finish.status === 200 && value(finish) === true &&
      jsonRows(ownerAfter).length === 0 && formerRows.length === 1 && Number(formerRows[0].total_amount_centavos) === 1200 &&
      formerPayments.length === 1 && formerPayments[0].id === secPaymentId &&
      finalRequest.status === 200 && jsonRows(finalRequest).length === 0,
    {deletion_completed: true, owner_api_access_revoked: true,
      counterpart_identity_redacted: true, former_counterpart_can_read_shared_expense_and_payment: true},
    {payment_submit_status: secPayment.status, payment_confirm_status: secConfirm.status,
      request_status: deletion.status, request_id: deletionId, owner_request_rows: jsonRows(requestAsOwner).length,
      counterpart_request_rows: jsonRows(requestAsCounterpart).length, review_status: review.status,
      review_body: review.body, prepare_status: prepare.status, prepare_body: prepare.body,
      pending_objects_status: pendingObjects.status, pending_objects_body: pendingObjects.body,
      pending_objects: value(pendingObjects), finish_status: finish.status, finish_result: value(finish),
      finish_body: finish.body,
      owner_after_status: ownerAfter.status, owner_after_rows: jsonRows(ownerAfter).length,
      counterpart_profile_before_status: counterpartProfileBefore.status,
      counterpart_profile_before_rows: jsonRows(counterpartProfileBefore).length,
      synthetic_profile_pii_was_seeded: syntheticPiiSeeded,
      synthetic_profile_seed: profileBefore,
      counterpart_profile_after_status: counterpartProfile.status,
      counterpart_profile_after: profileAfter && {display_name: profileAfter.display_name,
        email: profileAfter.email, phone: profileAfter.phone, avatar_url: profileAfter.avatar_url},
      former_counterpart_expense_status: formerCounterpartExpense.status, former_expense_rows: formerRows,
      former_counterpart_payment_status: formerCounterpartPayment.status, former_payment_rows: formerPayments,
      deletion_request_hidden_from_counterpart: finalRequest.status === 200 && jsonRows(finalRequest).length === 0,
      counterpart_profile_after: jsonRows(counterpartProfile)});
  results.sec005 = {export_owner_status: exportA.status, export_counterpart_status: exportB.status,
    owner_contact_present: actualOwnerContact, counterpart_leaks_owner_contact: otherExportLeaksContact,
    deletion_request_status: deletion.status, review_status: review.status, review_body: review.body,
    prepare_status: prepare.status, prepare_body: prepare.body,
    pending_objects: value(pendingObjects), finish_status: finish.status, finish_result: value(finish),
    finish_body: finish.body,
    owner_after_status: ownerAfter.status, owner_after_rows: jsonRows(ownerAfter).length,
    counterpart_profile_before_status: counterpartProfileBefore.status,
    counterpart_profile_before_rows: jsonRows(counterpartProfileBefore).length,
    synthetic_profile_pii_was_seeded: syntheticPiiSeeded,
    synthetic_profile_seed: profileBefore,
    storage_cleanup_ack_statuses: objectAcks.map(x => x.status),
    counterpart_profile_after_status: counterpartProfile.status,
    counterpart_profile_after: profileAfter && {display_name: profileAfter.display_name,
      email: profileAfter.email, phone: profileAfter.phone, avatar_url: profileAfter.avatar_url},
    former_counterpart_expenses: formerRows, former_counterpart_payments: formerPayments,
    deletion_request_hidden_from_counterpart: finalRequest.status === 200 && jsonRows(finalRequest).length === 0,
    note: 'local self-issued JWTs; direct SQL simulated Auth Admin deleted_at/session cleanup and Storage object removal'};

  return {assertions, results};
}
