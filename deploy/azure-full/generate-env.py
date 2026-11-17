"""Generate destination-only credentials on the VM, without printing secrets."""
import base64
import hashlib
import hmac
import json
import os
import secrets
import time
from pathlib import Path

destination = Path('/srv/tabby/.env')
if destination.exists():
    raise SystemExit('Refusing to replace existing destination credentials.')
template = Path('/srv/tabby/.env.example').read_text()
values = {}
for line in template.splitlines():
    if line and not line.startswith('#') and '=' in line:
        name, value = line.split('=', 1)
        values[name] = value
for name in ['POSTGRES_PASSWORD', 'JWT_SECRET', 'DASHBOARD_PASSWORD',
             'SECRET_KEY_BASE', 'VAULT_ENC_KEY', 'PG_META_CRYPTO_KEY',
             'LOGFLARE_PUBLIC_ACCESS_TOKEN', 'LOGFLARE_PRIVATE_ACCESS_TOKEN',
             'S3_PROTOCOL_ACCESS_KEY_ID', 'S3_PROTOCOL_ACCESS_KEY_SECRET']:
    values[name] = secrets.token_hex(32)
values['VAULT_ENC_KEY'] = secrets.token_hex(16)
values['REALTIME_DB_ENC_KEY'] = secrets.token_hex(8)


def encode(data):
    return base64.urlsafe_b64encode(data).rstrip(b'=').decode()


def token(role):
    now = int(time.time())
    header = encode(json.dumps({'alg': 'HS256', 'typ': 'JWT'}).encode())
    body = encode(json.dumps({'role': role, 'iss': 'supabase',
                              'iat': now, 'exp': now + 31536000}).encode())
    message = f'{header}.{body}'
    signature = hmac.new(values['JWT_SECRET'].encode(), message.encode(), hashlib.sha256).digest()
    return f'{message}.{encode(signature)}'


hostname = Path('/etc/tabby-hostname').read_text().strip()
values.update({
    'ANON_KEY': token('anon'),
    'SERVICE_ROLE_KEY': token('service_role'),
    'DASHBOARD_USERNAME': 'tabby-admin',
    'PROXY_DOMAIN': hostname,
    'SUPABASE_PUBLIC_URL': f'https://{hostname}',
    'API_EXTERNAL_URL': f'https://{hostname}/auth/v1',
    'SITE_URL': 'io.supabase.tabby://login-callback',
    'ADDITIONAL_REDIRECT_URLS': 'io.supabase.tabby://login-callback,io.supabase.tabby.usbtest://login-callback',
    'DISABLE_SIGNUP': 'true',
    'ENABLE_EMAIL_AUTOCONFIRM': 'false',
    'FUNCTIONS_VERIFY_JWT': 'true',
    'FUNCTIONS_MEMORY_LIMIT': '512m',
    'COMPOSE_FILE': 'docker-compose.yml:docker-compose.caddy.yml:docker-compose.private.yml',
    'STUDIO_DEFAULT_ORGANIZATION': 'Tabby',
    'STUDIO_DEFAULT_PROJECT': 'Azure migration destination',
})
fd = os.open(destination, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
with os.fdopen(fd, 'w') as output:
    output.write('\n'.join(f'{key}={value}' for key, value in values.items()) + '\n')
print('Destination-only credentials generated. Signup stays disabled pending migration.')
