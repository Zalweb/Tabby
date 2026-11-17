import copy
import importlib.util
from pathlib import Path
import unittest

spec = importlib.util.spec_from_file_location('registration', Path(__file__).with_name('configure-google-registration.py'))
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


def configuration():
    return {'services': {'auth': {'environment': {
        'GOTRUE_EXTERNAL_GOOGLE_ENABLED': 'true',
        'GOTRUE_EXTERNAL_GOOGLE_CLIENT_ID': 'synthetic-client',
        'GOTRUE_EXTERNAL_GOOGLE_SECRET': 'synthetic-secret',
        'GOTRUE_EXTERNAL_GOOGLE_REDIRECT_URI': module.CALLBACK,
        'GOTRUE_DISABLE_SIGNUP': 'true',
        'GOTRUE_HOOK_CUSTOM_ACCESS_TOKEN_URI': 'retained-hook',
        'GOTRUE_EXTERNAL_EMAIL_ENABLED': 'true',
        'GOTRUE_EXTERNAL_APPLE_ENABLED': 'true',
    }}, 'functions': {'environment': {'PRIVATE_WORKER': 'retained'}}}}


class RegistrationTests(unittest.TestCase):
    def test_only_provider_policy_changes_and_credentials_hooks_workers_retained(self):
        original = configuration()
        before = copy.deepcopy(original)
        result = module.patched_configuration(original, module.ORIGIN + '/auth/v1')
        self.assertEqual(original, before)
        auth = result['services']['auth']['environment']
        self.assertEqual(auth['GOTRUE_DISABLE_SIGNUP'], 'false')
        self.assertEqual(auth['GOTRUE_EXTERNAL_GOOGLE_ENABLED'], 'true')
        for name in ['EMAIL', 'PHONE', 'ANONYMOUS_USERS', 'APPLE']:
            self.assertEqual(auth['GOTRUE_EXTERNAL_' + name + '_ENABLED'], 'false')
        for key in ['GOTRUE_EXTERNAL_GOOGLE_CLIENT_ID', 'GOTRUE_EXTERNAL_GOOGLE_SECRET', 'GOTRUE_EXTERNAL_GOOGLE_REDIRECT_URI', 'GOTRUE_HOOK_CUSTOM_ACCESS_TOKEN_URI']:
            self.assertEqual(auth[key], before['services']['auth']['environment'][key])
        self.assertEqual(result['services']['functions'], before['services']['functions'])

    def test_wrong_origin_or_missing_existing_google_is_rejected(self):
        with self.assertRaises(ValueError):
            module.patched_configuration(configuration(), 'https://example.invalid/auth/v1')
        for field, value in [('GOTRUE_EXTERNAL_GOOGLE_ENABLED', 'false'), ('GOTRUE_EXTERNAL_GOOGLE_SECRET', ''), ('GOTRUE_EXTERNAL_GOOGLE_REDIRECT_URI', 'https://example.invalid/callback')]:
            value_config = configuration()
            value_config['services']['auth']['environment'][field] = value
            with self.assertRaises(ValueError):
                module.patched_configuration(value_config, module.ORIGIN + '/auth/v1')

    def test_idempotent_policy(self):
        first = module.patched_configuration(configuration(), module.ORIGIN + '/auth/v1')
        self.assertEqual(first, module.patched_configuration(first, module.ORIGIN + '/auth/v1'))

    def test_public_settings_require_google_only_and_enabled_signup(self):
        module.verify_settings({'disable_signup': False, 'external': {'google': True, 'email': False, 'phone': False}})
        for settings in [{'disable_signup': True, 'external': {'google': True}}, {'disable_signup': False, 'external': {'google': False}}, {'disable_signup': False, 'external': {'google': True, 'email': True}}, {'disable_signup': False, 'external': {'google': True, 'anonymous_users': True}}]:
            with self.assertRaises(ValueError):
                module.verify_settings(settings)


if __name__ == '__main__':
    unittest.main()
