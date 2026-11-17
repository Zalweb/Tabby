import copy
import importlib.util
from pathlib import Path
import unittest

spec = importlib.util.spec_from_file_location('callback', Path(__file__).with_name('configure-google-callback.py'))
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


def configuration():
    return {'services': {'auth': {'environment': {'GOTRUE_EXTERNAL_GOOGLE_ENABLED': 'true', 'GOTRUE_EXTERNAL_GOOGLE_CLIENT_ID': 'synthetic-public-id', 'GOTRUE_EXTERNAL_GOOGLE_SECRET': 'synthetic-private-value', 'GOTRUE_DISABLE_SIGNUP': 'true'}}, 'functions': {'environment': {'SYNTHETIC': 'retained'}}}}


class CallbackTests(unittest.TestCase):
    def test_only_callback_changes_and_input_credentials_are_untouched(self):
        original = configuration()
        before = copy.deepcopy(original)
        result = module.patched_configuration(original, module.ORIGIN + '/auth/v1')
        self.assertEqual(original, before)
        self.assertEqual(result['services']['auth']['environment'].pop(module.FIELD), module.CALLBACK)
        self.assertEqual(result, before)

    def test_unapproved_origin_or_unreviewed_callback_is_rejected(self):
        for url in ('http://example.invalid/auth/v1', module.ORIGIN + '/auth/v1?override=true', module.ORIGIN + '/different'):
            with self.assertRaises(ValueError):
                module.patched_configuration(configuration(), url)
        data = configuration()
        data['services']['auth']['environment'][module.FIELD] = 'https://elsewhere.invalid/callback'
        with self.assertRaises(ValueError):
            module.patched_configuration(data, module.ORIGIN + '/auth/v1')

    def test_disabled_or_missing_provider_credentials_fail_closed(self):
        for field, value in [('GOTRUE_EXTERNAL_GOOGLE_ENABLED', 'false'), ('GOTRUE_EXTERNAL_GOOGLE_SECRET', '')]:
            data = configuration()
            data['services']['auth']['environment'][field] = value
            with self.assertRaises(ValueError):
                module.patched_configuration(data, module.ORIGIN + '/auth/v1')

    def test_credential_repair_changes_only_secret_for_the_same_client(self):
        original = configuration()
        auth = original['services']['auth']['environment']
        auth['GOTRUE_EXTERNAL_GOOGLE_CLIENT_ID'] = module.CLIENT_ID
        auth[module.FIELD] = module.CALLBACK
        before = copy.deepcopy(original)
        incoming = {'client_id': module.CLIENT_ID, 'client_secret': 'synthetic-private-secret-for-test'}
        result = module.patched_credentials(original, incoming)
        self.assertEqual(original, before)
        self.assertEqual(result['services']['auth']['environment'].pop('GOTRUE_EXTERNAL_GOOGLE_SECRET'), incoming['client_secret'])
        before['services']['auth']['environment'].pop('GOTRUE_EXTERNAL_GOOGLE_SECRET')
        self.assertEqual(result, before)

    def test_wrong_client_and_malformed_secret_are_rejected(self):
        for incoming in ({'client_id': 'different-client', 'client_secret': 'synthetic-private-secret-for-test'}, {'client_id': module.CLIENT_ID, 'client_secret': ''}, {'client_id': module.CLIENT_ID, 'client_secret': '${INJECTED_VARIABLE}'}):
            with self.assertRaises(ValueError):
                module.patched_credentials(configuration(), incoming)


if __name__ == '__main__':
    unittest.main()
