import copy
import importlib.util
import unittest
from pathlib import Path

spec = importlib.util.spec_from_file_location('firebase', Path(__file__).with_name('configure-firebase.py'))
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class ConfigurationTests(unittest.TestCase):
    def setUp(self):
        self.config = {'services': {'auth': {'environment': {'SYNTHETIC_AUTH': 'preserve'}}, 'functions': {'environment': {'PUSH_WORKER_SECRET': 'synthetic-worker-secret-for-regression-only', 'OTHER_WORKER': 'preserve'}}}}
        self.identity = {'type': 'external_account', 'audience': module.AUDIENCE, 'service_account_impersonation_url': 'https://iamcredentials.googleapis.com/v1/projects/-/serviceAccounts/tabby-push-sender@' + module.PROJECT + '.iam.gserviceaccount.com:generateAccessToken'}

    def test_only_two_functions_fields_change_without_mutating_input(self):
        before = copy.deepcopy(self.config)
        result = module.patched_configuration(self.config, self.identity)
        self.assertEqual(self.config, before)
        env = result['services']['functions']['environment']
        self.assertEqual(env.pop('FIREBASE_PROJECT_ID'), module.PROJECT)
        self.assertIn('external_account', env.pop('FIREBASE_WORKLOAD_IDENTITY_JSON'))
        self.assertEqual(result, before)

    def test_wrong_project_provider_or_key_material_is_rejected(self):
        for key, value in [('audience', 'different'), ('type', 'service_account'), ('private_key', 'synthetic'), ('service_account_impersonation_url', 'https://example.invalid/token')]:
            with self.assertRaises(ValueError):
                module.patched_configuration(self.config, {**self.identity, key: value})

    def test_worker_authentication_and_prior_project_are_preserved(self):
        for field, value in [('PUSH_WORKER_SECRET', ''), ('FIREBASE_PROJECT_ID', 'other-project')]:
            config = copy.deepcopy(self.config)
            config['services']['functions']['environment'][field] = value
            with self.assertRaises(ValueError):
                module.patched_configuration(config, self.identity)


if __name__ == '__main__':
    unittest.main()
