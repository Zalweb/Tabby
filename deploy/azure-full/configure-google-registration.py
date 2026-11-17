"""Enable only the reviewed Google registration flow on the existing target.

Supabase Auth documents that DISABLE_SIGNUP blocks OAuth creation too, while
EXTERNAL_EMAIL_ENABLED=false preserves external OAuth sign-up/sign-in.
https://supabase.github.io/auth/#top-level
No user/ledger mutation or credential replacement is performed here.
"""
import copy
import json
import re

ORIGIN = 'https://tabby-7abf436e-20261113.eastasia.cloudapp.azure.com'
CALLBACK = ORIGIN + '/auth/v1/callback'
POLICY = {
    'GOTRUE_DISABLE_SIGNUP': 'false',
    'GOTRUE_EXTERNAL_EMAIL_ENABLED': 'false',
    'GOTRUE_EXTERNAL_PHONE_ENABLED': 'false',
    'GOTRUE_EXTERNAL_ANONYMOUS_USERS_ENABLED': 'false',
    'GOTRUE_EXTERNAL_GOOGLE_ENABLED': 'true',
}


def patched_configuration(configuration, origin):
    if origin.rstrip('/') != ORIGIN + '/auth/v1':
        raise ValueError('Only the approved existing Auth target is allowed')
    result = copy.deepcopy(configuration)
    auth = result['services']['auth']['environment']
    if str(auth.get('GOTRUE_EXTERNAL_GOOGLE_ENABLED')).lower() != 'true':
        raise ValueError('Existing Google configuration required')
    if not auth.get('GOTRUE_EXTERNAL_GOOGLE_CLIENT_ID') or not auth.get('GOTRUE_EXTERNAL_GOOGLE_SECRET'):
        raise ValueError('Existing Google credentials required')
    if auth.get('GOTRUE_EXTERNAL_GOOGLE_REDIRECT_URI') != CALLBACK:
        raise ValueError('Reviewed Google callback required')
    for key, value in list(auth.items()):
        if re.fullmatch(r'GOTRUE_EXTERNAL_[A-Z0-9_]+_ENABLED', key) and key != 'GOTRUE_EXTERNAL_GOOGLE_ENABLED':
            auth[key] = 'false'
    auth.update(POLICY)
    return result


def verify_settings(settings):
    external = settings.get('external', {})
    if settings.get('disable_signup') is not False or external.get('google') is not True:
        raise ValueError('Google registration is not enabled')
    if any(value is True for name, value in external.items() if name != 'google'):
        raise ValueError('Unexpected additional registration provider')


def main():
    import base64
    import datetime
    import hashlib
    import os
    import secrets
    import subprocess
    import time
    import urllib.error
    import urllib.request
    from pathlib import Path
    from cryptography.hazmat.primitives import hashes, serialization
    from cryptography.hazmat.primitives.asymmetric import padding
    from cryptography.hazmat.primitives.ciphers.aead import AESGCM

    os.umask(0o077)
    root = Path('/srv/tabby')
    config = root / 'docker-compose.tabby.yml'
    marker = root / 'migration/google-only-registration.json'
    raw = config.read_bytes()
    old_marker = marker.read_bytes() if marker.exists() else None
    env = dict(line.split('=', 1) for line in (root / '.env').read_text().splitlines() if '=' in line and not line.startswith('#'))
    result = patched_configuration(json.loads(raw), env['API_EXTERNAL_URL'].strip('"\''))
    private = serialization.load_pem_private_key((root / 'migration-private.pem').read_bytes(), password=None)
    stamp = datetime.datetime.now(datetime.timezone.utc).strftime('%Y%m%dT%H%M%SZ') + '-' + secrets.token_hex(3)
    folder = root / 'migration' / ('google-registration-' + stamp)
    folder.mkdir(mode=0o700)
    plaintext = json.dumps({'compose': base64.b64encode(raw).decode(), 'marker': base64.b64encode(old_marker).decode() if old_marker else None}).encode()
    key, iv = os.urandom(32), os.urandom(12)
    encrypted = AESGCM(key).encrypt(iv, plaintext, None)
    backup = json.dumps({'algorithm': 'RSA-OAEP-SHA256+A256GCM', 'wrappedKey': base64.b64encode(private.public_key().encrypt(key, padding.OAEP(mgf=padding.MGF1(hashes.SHA256()), algorithm=hashes.SHA256(), label=None))).decode(), 'iv': base64.b64encode(iv).decode(), 'ciphertext': base64.b64encode(encrypted).decode()}).encode()
    backup_path = folder / 'configuration-before.sealed.json'
    with backup_path.open('xb') as handle:
        handle.write(backup)
        handle.flush()
        os.fsync(handle.fileno())
    saved = json.loads(backup_path.read_bytes())
    recovered_key = private.decrypt(base64.b64decode(saved['wrappedKey']), padding.OAEP(mgf=padding.MGF1(hashes.SHA256()), algorithm=hashes.SHA256(), label=None))
    if AESGCM(recovered_key).decrypt(base64.b64decode(saved['iv']), base64.b64decode(saved['ciphertext']), None) != plaintext:
        raise ValueError('Encrypted backup readback failed')
    report = {'run_id': folder.name, 'outcome': 'failed', 'operator_sha256': hashlib.sha256(Path(__file__).read_bytes()).hexdigest(), 'backup_ciphertext_sha256': hashlib.sha256(backup).hexdigest(), 'backup_recovery_verified': True, 'credentials_changed': False, 'financial_data_changed': False, 'user_accounts_created': False, 'restarted_service': 'auth', 'auth_image': 'supabase/gotrue:v2.197.0'}

    def write(target, data):
        temp = target.with_suffix('.registration.tmp')
        with temp.open('wb') as handle:
            handle.write(data)
            handle.flush()
            os.fsync(handle.fileno())
        os.replace(temp, target)

    def recreate():
        done = subprocess.run(['docker', 'compose', 'up', '-d', '--no-deps', '--force-recreate', 'auth'], cwd=root, capture_output=True, timeout=180)
        if done.returncode:
            raise RuntimeError('Auth recreation failed; private output withheld')
        for _ in range(60):
            health = subprocess.run(['docker', 'inspect', '--format', '{{.State.Health.Status}}', 'supabase-auth'], capture_output=True, timeout=10)
            if health.returncode == 0 and health.stdout.strip() == b'healthy':
                return
            time.sleep(2)
        raise RuntimeError('Auth did not become healthy')

    def request(path, data=None):
        req = urllib.request.Request(ORIGIN + '/auth/v1/' + path,
            data=json.dumps(data).encode() if data is not None else None,
            headers={'apikey': env['ANON_KEY'].strip('"\''), 'Content-Type': 'application/json'})
        try:
            with urllib.request.urlopen(req, timeout=30) as response:
                return response.status, json.load(response)
        except urllib.error.HTTPError as error:
            return error.code, json.load(error)

    try:
        write(config, json.dumps(result, indent=2).encode() + b'\n')
        write(marker, json.dumps({'version': 1, 'policy': POLICY, 'decision': 'DEC-013'}).encode())
        recreate()
        status, settings = request('settings')
        if status != 200:
            raise ValueError('Auth settings unavailable')
        verify_settings(settings)
        probes = {}
        for label, path, payload in [
            ('email_signup', 'signup', {'email': 'qa025-synthetic@example.invalid', 'password': secrets.token_urlsafe(32)}),
            ('phone_signup', 'signup', {'phone': '+639990000025', 'password': secrets.token_urlsafe(32)}),
            ('anonymous_signup', 'signup', {}),
            ('email_password', 'token?grant_type=password', {'email': 'qa025-synthetic@example.invalid', 'password': secrets.token_urlsafe(32)}),
        ]:
            code, body = request(path, payload)
            if code < 400 or any(key in body for key in ['access_token', 'user', 'id', 'confirmation_sent_at']):
                raise ValueError('Disabled entry probe unexpectedly accepted')
            probes[label] = {'http_status': code, 'error_code': body.get('error_code') or body.get('code')}
        report.update(outcome='passed', auth_healthy=True, google_enabled=True, registration_enabled=True, other_providers_enabled=False, disabled_entry_probes=probes, policy_persisted=True)
    except Exception as error:
        report['error_type'] = type(error).__name__
        write(config, raw)
        if old_marker is None:
            marker.unlink(missing_ok=True)
        else:
            write(marker, old_marker)
        try:
            recreate()
            report['rollback'] = 'passed'
        except Exception:
            report['rollback'] = 'failed; operator attention required'
    (folder / 'result.json').write_text(json.dumps(report))
    print(json.dumps(report), flush=True)
    return 0 if report['outcome'] == 'passed' else 2


if __name__ == '__main__':
    raise SystemExit(main())
