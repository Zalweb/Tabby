import copy
import importlib.util
import unittest
from pathlib import Path

spec = importlib.util.spec_from_file_location('readiness', Path(__file__).with_name('apply-readiness-patch.py'))
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
root = Path(__file__).resolve().parents[2]


def packet():
    migrations = []
    for version in module.APPROVED:
        path = next((root / 'supabase/migrations').glob(version + '_*.sql'))
        migrations.append({'version': version, 'name': path.stem.split('_', 1)[1], 'sql': path.read_bytes().decode()})
    return {'run_id': 'readiness-20261114T052000Z-0123abcd', 'migrations': migrations, 'backup_url': 'https://' + module.HOST + '/migration-private/readiness-20261114T052000Z-0123abcd-prepatch.sealed.json?sp=rcw&spr=https&sig=synthetic', 'recovery_public_key': '-----BEGIN PUBLIC KEY-----synthetic'}


class PatchTests(unittest.TestCase):
    def test_exact_reviewed_source_rehearses_then_commits_explicitly(self):
        data = packet()
        module.validate_packet(data)
        self.assertTrue(module.patch_sql(data).endswith('ROLLBACK;'))
        self.assertTrue(module.patch_sql(data, commit=True).endswith('COMMIT;'))
        self.assertIn('Financial history changed', module.patch_sql(data))

    def test_drift_extra_or_reordered_migrations_are_rejected(self):
        for mutate in (lambda p: p['migrations'][0].update(sql='SELECT 1;'), lambda p: p['migrations'].reverse(), lambda p: p['migrations'].append(copy.deepcopy(p['migrations'][0]))):
            data = packet()
            mutate(data)
            with self.assertRaises(ValueError):
                module.validate_packet(data)

    def test_backup_cannot_be_sent_to_other_host_container_or_permissions(self):
        for value in ('https://example.invalid/private?sp=rcw&spr=https', packet()['backup_url'].replace('/migration-private/', '/public/'), packet()['backup_url'].replace('sp=rcw', 'sp=rcwd'), packet()['backup_url'].replace('https://', 'http://')):
            data = packet()
            data['backup_url'] = value
            with self.assertRaises(ValueError):
                module.validate_packet(data)

    def test_run_identifier_cannot_escape_private_patch_directory(self):
        data = packet()
        data['run_id'] = '../other'
        with self.assertRaises(ValueError):
            module.validate_packet(data)


if __name__ == '__main__':
    unittest.main()
