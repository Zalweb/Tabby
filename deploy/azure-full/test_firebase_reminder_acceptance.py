import importlib.util
import unittest
from pathlib import Path

spec = importlib.util.spec_from_file_location('acceptance', Path(__file__).with_name('verify-firebase-reminders.py'))
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class AcceptanceGuards(unittest.TestCase):
    def test_new_reminder_preserves_expense_and_original_event(self):
        one = '00000000-0000-4000-8000-000000000001'
        two = '00000000-0000-4000-8000-000000000002'
        state = dict(phase='provider_accepted_await_native_delivery', expense=one,
                     notification=one, job=one, binding=one, reminder_operation=one,
                     expense_operation=two)
        module.prepare_new_reminder(state, two)
        self.assertEqual(state['expense'], one)
        self.assertEqual(state['expense_operation'], two)
        self.assertEqual(state['prior_events'][0]['notification'], one)
        self.assertNotEqual(state['reminder_operation'], one)
        self.assertNotIn('notification', state)
        with self.assertRaises(ValueError):
            module.prepare_new_reminder(state, two)

    def test_only_unqueued_fixture_may_capture_renewed_binding(self):
        old = '00000000-0000-4000-8000-000000000001'
        new = '00000000-0000-4000-8000-000000000002'
        state = {'binding': old, 'phase': 'await_recipient_acceptance'}
        self.assertEqual(module.queue_binding(state, None), old)
        self.assertEqual(module.queue_binding(state, new), new)
        for change in [{'expense': old}, {'notification': old}, {'phase': 'ready_for_manual_worker'}]:
            with self.assertRaises(ValueError):
                module.queue_binding({**state, **change}, new)

    def test_psql_boolean_and_json_shapes_are_distinct(self):
        self.assertIs(module.parse_psql('t\n'), True)
        self.assertIs(module.parse_psql('f\n'), False)
        self.assertEqual(module.parse_psql('[{"id":"synthetic"}]\n'), [{'id': 'synthetic'}])
        with self.assertRaises(ValueError):
            module.parse_psql('unexpected diagnostic')

    def test_dispatch_refuses_any_other_job_or_device(self):
        exact = {'target_pending': 1, 'all_pending_or_sending': 1, 'other_active_bindings': 0}
        self.assertTrue(module.dispatch_scope_allowed(exact))
        for key, value in [('target_pending', 0), ('target_pending', 2), ('all_pending_or_sending', 2), ('other_active_bindings', 1)]:
            self.assertFalse(module.dispatch_scope_allowed({**exact, key: value}))

    def test_only_canonical_fixture_ids_and_reviewed_rpc_names(self):
        actor = '00000000-0000-4000-8000-000000000001'
        self.assertIn('SET LOCAL ROLE authenticated', module.actor_rpc_sql(actor, 'send_friend_request', {'p_friend_code': 'SYNTHETIC'}))
        for name in ['process_account_deletion_v1', 'confirm_payment', 'unsafe;DROP TABLE public.users']:
            with self.assertRaises(ValueError):
                module.actor_rpc_sql(actor, name, {})
        with self.assertRaises(ValueError):
            module.actor_rpc_sql('not-a-uuid', 'send_friend_request', {})

    def test_rpc_inputs_are_quoted_as_data(self):
        actor = '00000000-0000-4000-8000-000000000001'
        sql = module.actor_rpc_sql(actor, 'send_friend_request', {'p_friend_code': "x');SELECT 1;--"})
        self.assertIn("'x'');SELECT 1;--'::text", sql)
        with self.assertRaises(ValueError):
            module.actor_rpc_sql(actor, 'send_friend_request', {'p_code;SELECT 1': 'SYNTHETIC'})


if __name__ == '__main__':
    unittest.main()
