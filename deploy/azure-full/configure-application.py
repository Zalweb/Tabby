"""Install actual Tabby workers and source Google configuration, without cron."""
import base64
import json
import os
import secrets
from pathlib import Path
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import padding
from cryptography.hazmat.primitives.ciphers.aead import AESGCM

os.umask(0o077)
root = Path('/srv/tabby/migration')
private = serialization.load_pem_private_key(Path('/srv/tabby/migration-private.pem').read_bytes(), password=None)


def unseal(file):
    envelope = json.loads(file.read_text())
    key = private.decrypt(base64.b64decode(envelope['wrappedKey']), padding.OAEP(mgf=padding.MGF1(hashes.SHA256()), algorithm=hashes.SHA256(), label=None))
    return json.loads(AESGCM(key).decrypt(base64.b64decode(envelope['iv']), base64.b64decode(envelope['ciphertext']) + base64.b64decode(envelope['tag']), None))


packet = unseal(root / 'application-capsule.json')
source = unseal(root / 'source-assets.sealed.json')['auth_config']
google_override = root / 'google-provider-current.sealed.json'
if google_override.exists():
    current_google = unseal(google_override)
    source.update(external_google_client_id=current_google['client_id'], external_google_secret=current_google['client_secret'])
allowed = {'reminder-push/index.ts', 'reminder-push/worker.mjs', 'recurring-obligations/index.ts', 'recurring-obligations/worker.mjs', 'account-deletion/index.ts', 'account-deletion/worker.mjs'}
if set(packet['files']) != allowed:
    raise SystemExit('Unexpected worker bundle.')
for name, contents in packet['files'].items():
    target = Path('/srv/tabby/volumes/functions') / name
    target.parent.mkdir(mode=0o700, exist_ok=True)
    target.write_text(contents)
Path('/srv/tabby/docker-compose.private.yml').write_text(packet['compose_private'])
config_path = Path('/srv/tabby/docker-compose.tabby.yml')
config = json.loads(config_path.read_text()) if config_path.exists() else {'services': {'auth': {'environment': {}}, 'functions': {'environment': {}}}}
auth = config['services']['auth']['environment']
google = source.get('external_google_enabled', False)
if google:
    client, secret = source.get('external_google_client_id', ''), source.get('external_google_secret', '')
    if not client or not secret or set(secret) <= {'*'}:
        raise SystemExit('Google provider credentials require private input; values withheld.')
    auth.update({'GOTRUE_EXTERNAL_GOOGLE_ENABLED': 'true', 'GOTRUE_EXTERNAL_GOOGLE_CLIENT_ID': client.replace('$','$$'), 'GOTRUE_EXTERNAL_GOOGLE_SECRET': secret.replace('$','$$'), 'GOTRUE_EXTERNAL_GOOGLE_SKIP_NONCE_CHECK': str(source.get('external_google_skip_nonce_check', False)).lower()})
    auth['GOTRUE_EXTERNAL_GOOGLE_REDIRECT_URI'] = 'https://tabby-7abf436e-20261113.eastasia.cloudapp.azure.com/auth/v1/callback'
functions = config['services']['functions']['environment']
registration_policy = root / 'google-only-registration.json'
if registration_policy.exists():
    policy = json.loads(registration_policy.read_text())
    expected = {'GOTRUE_DISABLE_SIGNUP': 'false', 'GOTRUE_EXTERNAL_EMAIL_ENABLED': 'false',
                'GOTRUE_EXTERNAL_PHONE_ENABLED': 'false', 'GOTRUE_EXTERNAL_ANONYMOUS_USERS_ENABLED': 'false',
                'GOTRUE_EXTERNAL_GOOGLE_ENABLED': 'true'}
    if policy.get('version') != 1 or policy.get('policy') != expected or not google:
        raise SystemExit('Unexpected Google-only registration policy; review required.')
    for key in list(auth):
        if key.startswith('GOTRUE_EXTERNAL_') and key.endswith('_ENABLED') and key != 'GOTRUE_EXTERNAL_GOOGLE_ENABLED':
            auth[key] = 'false'
    auth.update(expected)
for name in ['PUSH_WORKER_SECRET', 'RECURRENCE_WORKER_SECRET', 'PRIVACY_REVIEW_SECRET']:
    if not functions.get(name):
        functions[name] = secrets.token_hex(32)
config_path.write_text(json.dumps(config, indent=2))
env_path = Path('/srv/tabby/.env')
lines = env_path.read_text().splitlines()
lines = [line + ':docker-compose.tabby.yml' if line.startswith('COMPOSE_FILE=') and 'docker-compose.tabby.yml' not in line else line for line in lines]
env_path.write_text('\n'.join(lines) + '\n')
print(json.dumps({'stage': 'application-config', 'outcome': 'passed', 'workers': 3, 'google_credentials_copied': google, 'worker_secrets': 'destination generated', 'schedulers': 'disabled', 'firebase_push_credentials': 'not configured', 'smtp': 'pending private service key', 'google_callback_acceptance': 'unverified'}), flush=True)
