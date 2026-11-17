"""Repair only the reviewed Google callback on the existing migration target."""
import copy
import json
import urllib.parse

ORIGIN = 'https://tabby-7abf436e-20261113.eastasia.cloudapp.azure.com'
CALLBACK = ORIGIN + '/auth/v1/callback'
FIELD = 'GOTRUE_EXTERNAL_GOOGLE_REDIRECT_URI'
CLIENT_ID = '137141086000-p2o6c1hminjif8i5f739n3a6ils7ucmm.apps.googleusercontent.com'


def patched_configuration(configuration, api_external_url):
    parsed = urllib.parse.urlparse(api_external_url)
    if api_external_url.rstrip('/') != ORIGIN + '/auth/v1' or parsed.query or parsed.fragment:
        raise ValueError('Only the approved migration Auth origin is allowed')
    result = copy.deepcopy(configuration)
    auth = result['services']['auth']['environment']
    if str(auth.get('GOTRUE_EXTERNAL_GOOGLE_ENABLED')).lower() != 'true':
        raise ValueError('Existing Google provider must already be enabled')
    if not auth.get('GOTRUE_EXTERNAL_GOOGLE_CLIENT_ID') or not auth.get('GOTRUE_EXTERNAL_GOOGLE_SECRET'):
        raise ValueError('Existing private Google credentials required')
    if auth.get(FIELD) not in (None, '', CALLBACK):
        raise ValueError('Unexpected existing provider callback; review required')
    auth[FIELD] = CALLBACK
    return result


def patched_credentials(configuration, provider):
    import re
    if set(provider) != {'client_id', 'client_secret'} or provider['client_id'] != CLIENT_ID:
        raise ValueError('Only the existing approved Web client is allowed')
    if not isinstance(provider['client_secret'], str) or not re.fullmatch(r'[A-Za-z0-9_-]{20,200}', provider['client_secret']):
        raise ValueError('Private client secret is missing or malformed')
    result = copy.deepcopy(configuration)
    auth = result['services']['auth']['environment']
    if auth['GOTRUE_EXTERNAL_GOOGLE_CLIENT_ID'].split(',')[0] != CLIENT_ID or auth.get(FIELD) != CALLBACK:
        raise ValueError('Existing provider identity/callback differs from review')
    auth['GOTRUE_EXTERNAL_GOOGLE_SECRET'] = provider['client_secret']
    return result


def main():
    import argparse
    import base64
    import datetime
    import hashlib
    import os
    import secrets
    import subprocess
    import time
    import urllib.request
    import urllib.error
    from pathlib import Path
    from cryptography.hazmat.primitives import hashes, serialization
    from cryptography.hazmat.primitives.asymmetric import padding
    from cryptography.hazmat.primitives.ciphers.aead import AESGCM

    os.umask(0o077)
    parser = argparse.ArgumentParser()
    parser.add_argument('--sealed-credentials')
    args = parser.parse_args()
    root = Path('/srv/tabby')
    path = root / 'docker-compose.tabby.yml'
    raw = path.read_bytes()
    configuration = json.loads(raw)
    env = dict(line.split('=', 1) for line in (root / '.env').read_text().splitlines() if '=' in line and not line.startswith('#'))
    result = patched_configuration(configuration, env['API_EXTERNAL_URL'].strip('"\''))
    private = serialization.load_pem_private_key((root / 'migration-private.pem').read_bytes(), password=None)
    override = root / 'migration/google-provider-current.sealed.json'
    prior_override = override.read_bytes() if override.exists() else None
    incoming = None
    if args.sealed_credentials:
        incoming_path = Path(args.sealed_credentials)
        if incoming_path != root / 'migration/qa022-google-credentials.sealed.json':
            raise ValueError('Expected reviewed private credential capsule path')
        incoming = incoming_path.read_bytes()
        envelope = json.loads(incoming)
        wrapped = private.decrypt(base64.b64decode(envelope['wrappedKey']), padding.OAEP(mgf=padding.MGF1(hashes.SHA256()), algorithm=hashes.SHA256(), label=None))
        provider = json.loads(AESGCM(wrapped).decrypt(base64.b64decode(envelope['iv']), base64.b64decode(envelope['ciphertext']) + base64.b64decode(envelope['tag']), None))
        result = patched_credentials(result, provider)
        # A deliberately invalid code checks client authentication without a
        # real user's code or creating a session. Wrong credentials fail first.
        request = urllib.request.Request('https://oauth2.googleapis.com/token', method='POST', data=urllib.parse.urlencode({**provider, 'code': 'synthetic-invalid-code-for-credential-diagnostic', 'grant_type': 'authorization_code', 'redirect_uri': CALLBACK}).encode(), headers={'Content-Type': 'application/x-www-form-urlencoded'})
        try:
            urllib.request.urlopen(request, timeout=30)
            raise ValueError('Unexpected synthetic credential-check response')
        except urllib.error.HTTPError as error:
            answer = json.load(error)
            if error.code != 400 or answer.get('error') != 'invalid_grant':
                raise ValueError('Google rejected incoming client credentials') from None
    stamp = datetime.datetime.now(datetime.timezone.utc).strftime('%Y%m%dT%H%M%SZ') + '-' + secrets.token_hex(3)
    folder = root / 'migration' / ('oauth-callback-' + stamp)
    folder.mkdir(mode=0o700)
    key, iv = os.urandom(32), os.urandom(12)
    backup_plaintext = json.dumps({'compose': base64.b64encode(raw).decode(), 'provider_override': base64.b64encode(prior_override).decode() if prior_override else None}).encode()
    ciphertext = AESGCM(key).encrypt(iv, backup_plaintext, None)
    backup = json.dumps({'algorithm': 'RSA-OAEP-SHA256+A256GCM', 'wrappedKey': base64.b64encode(private.public_key().encrypt(key, padding.OAEP(mgf=padding.MGF1(hashes.SHA256()), algorithm=hashes.SHA256(), label=None))).decode(), 'iv': base64.b64encode(iv).decode(), 'ciphertext': base64.b64encode(ciphertext).decode()}).encode()
    backup_path = folder / 'compose-before.sealed.json'
    with backup_path.open('xb') as handle:
        handle.write(backup)
        handle.flush()
        os.fsync(handle.fileno())
    if AESGCM(key).decrypt(iv, ciphertext, None) != backup_plaintext:
        raise ValueError('Encrypted backup recovery verification failed')
    report = {'run_id': folder.name, 'outcome': 'failed', 'callback': CALLBACK, 'configuration_fields': [FIELD] + (['GOTRUE_EXTERNAL_GOOGLE_SECRET'] if incoming else []), 'backup_ciphertext_sha256': hashlib.sha256(backup).hexdigest(), 'backup_recovery_verified': True, 'credentials_changed': bool(incoming), 'incoming_credential_probe': 'invalid_grant for synthetic code; client accepted' if incoming else 'not requested', 'financial_data_changed': False, 'signup_changed': False, 'restarted_service': 'auth'}
    report['operator_sha256'] = hashlib.sha256(Path(__file__).read_bytes()).hexdigest()

    def write_file(target, data):
        temporary = target.with_suffix('.oauth-update.tmp')
        with temporary.open('wb') as handle:
            handle.write(data)
            handle.flush()
            os.fsync(handle.fileno())
        os.replace(temporary, target)

    def recreate():
        operation = subprocess.run(['docker', 'compose', 'up', '-d', '--no-deps', '--force-recreate', 'auth'], cwd=root, capture_output=True, timeout=180)
        if operation.returncode:
            raise RuntimeError('Auth recreation failed; private output withheld')
        for _ in range(60):
            health = subprocess.run(['docker', 'inspect', '--format', '{{.State.Health.Status}}', 'supabase-auth'], capture_output=True, timeout=10)
            if health.returncode == 0 and health.stdout.strip() == b'healthy':
                return
            time.sleep(2)
        raise RuntimeError('Auth health did not recover')

    try:
        if incoming:
            write_file(override, incoming)
        write_file(path, json.dumps(result, indent=2).encode() + b'\n')
        recreate()
        request = urllib.request.Request(ORIGIN + '/auth/v1/settings', headers={'apikey': env['ANON_KEY'].strip('"\'')})
        with urllib.request.urlopen(request, timeout=30) as response:
            settings = json.load(response)
        google_only = root / 'migration/google-only-registration.json'
        expected_disabled = not google_only.exists()
        if settings.get('disable_signup') is not expected_disabled or settings.get('external', {}).get('google') is not True:
            raise ValueError('Existing Auth safeguards/provider state changed')
        if not expected_disabled and any(value is True for name, value in settings.get('external', {}).items() if name != 'google'):
            raise ValueError('Google-only registration policy changed')
        report.update(outcome='passed', auth_healthy=True, signup_still_disabled=expected_disabled, encrypted_provider_override_saved=bool(incoming))
    except Exception as error:
        report['error_type'] = type(error).__name__
        write_file(path, raw)
        if incoming:
            if prior_override is not None:
                write_file(override, prior_override)
            else:
                override.unlink(missing_ok=True)
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
