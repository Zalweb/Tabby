"""Apply the reviewed keyless sender to the existing Azure functions service."""
import copy
import hashlib
import json

PROJECT = 'project-16899afb-9d76-433c-9a2'
AUDIENCE = '//iam.googleapis.com/projects/794974227784/locations/global/workloadIdentityPools/tabby-azure/providers/supabase-vm'
FILES = ('reminder-push/index.ts', 'reminder-push/worker.mjs')


def patched_configuration(configuration, identity):
    if identity.get('type') != 'external_account' or identity.get('audience') != AUDIENCE:
        raise ValueError('Only reviewed keyless VM sender is supported')
    if identity.get('service_account_impersonation_url') != 'https://iamcredentials.googleapis.com/v1/projects/-/serviceAccounts/tabby-push-sender@' + PROJECT + '.iam.gserviceaccount.com:generateAccessToken':
        raise ValueError('Unexpected FCM sender identity')
    if any(key in identity for key in ('private_key', 'client_secret', 'refresh_token')):
        raise ValueError('Keyless sender must not contain private credentials')
    result = copy.deepcopy(configuration)
    functions = result['services']['functions']['environment']
    if len(functions.get('PUSH_WORKER_SECRET', '')) < 32:
        raise ValueError('Existing worker authentication is required')
    existing = functions.get('FIREBASE_PROJECT_ID')
    if existing not in (None, '', PROJECT):
        raise ValueError('Unexpected prior FCM project')
    functions.update(FIREBASE_PROJECT_ID=PROJECT, FIREBASE_WORKLOAD_IDENTITY_JSON=json.dumps(identity, separators=(',', ':')))
    return result


def main():
    import base64
    import datetime
    import os
    import secrets
    import subprocess
    import time
    import urllib.request
    from pathlib import Path
    from cryptography.hazmat.primitives import hashes, serialization
    from cryptography.hazmat.primitives.asymmetric import padding
    from cryptography.hazmat.primitives.ciphers.aead import AESGCM

    os.umask(0o077)
    root = Path('/srv/tabby')
    packet = json.loads((root / 'migration/qa018-firebase-packet.json').read_text())
    if set(packet) != {'identity', 'files', 'expected_before_sha256'} or set(packet['files']) != set(FILES) or set(packet['expected_before_sha256']) != set(FILES):
        raise ValueError('Only the two reviewed push files may change')
    compose = root / 'docker-compose.tabby.yml'
    raw = compose.read_bytes()
    configuration = json.loads(raw)
    result = patched_configuration(configuration, packet['identity'])
    previous = {'compose': base64.b64encode(raw).decode(), 'files': {}}
    paths = {name: root / 'volumes/functions' / name for name in FILES}
    for name, path in paths.items():
        before = path.read_bytes()
        if hashlib.sha256(before).hexdigest() != packet['expected_before_sha256'][name]:
            raise ValueError('Remote worker differs from reviewed baseline')
        previous['files'][name] = base64.b64encode(before).decode()
    folder = root / 'migration' / ('firebase-' + datetime.datetime.now(datetime.timezone.utc).strftime('%Y%m%dT%H%M%SZ') + '-' + secrets.token_hex(3))
    folder.mkdir(mode=0o700)
    private = serialization.load_pem_private_key((root / 'migration-private.pem').read_bytes(), password=None)
    plaintext = json.dumps(previous).encode()
    key, iv = os.urandom(32), os.urandom(12)
    encrypted = AESGCM(key).encrypt(iv, plaintext, None)
    if AESGCM(key).decrypt(iv, encrypted, None) != plaintext:
        raise ValueError('Encrypted recovery integrity check failed')
    backup = json.dumps({'algorithm': 'RSA-OAEP-SHA256+A256GCM', 'wrappedKey': base64.b64encode(private.public_key().encrypt(key, padding.OAEP(mgf=padding.MGF1(hashes.SHA256()), algorithm=hashes.SHA256(), label=None))).decode(), 'iv': base64.b64encode(iv).decode(), 'ciphertext': base64.b64encode(encrypted).decode()}).encode()
    (folder / 'before.sealed.json').write_bytes(backup)
    report = {'run_id': folder.name, 'outcome': 'failed', 'project_id': PROJECT, 'restarted_service': 'functions', 'backup_recovery_verified': True, 'backup_ciphertext_sha256': hashlib.sha256(backup).hexdigest(), 'operator_sha256': hashlib.sha256(Path(__file__).read_bytes()).hexdigest(), 'worker_sha256': {name: hashlib.sha256(packet['files'][name].encode()).hexdigest() for name in FILES}, 'auth_configuration_changed': False, 'financial_data_changed': False, 'scheduler_enabled': False}

    def write(target, data):
        temporary = target.with_suffix('.firebase.tmp')
        with temporary.open('wb') as handle:
            handle.write(data)
            handle.flush()
            os.fsync(handle.fileno())
        os.replace(temporary, target)

    def recreate():
        step = subprocess.run(['docker', 'compose', 'up', '-d', '--no-deps', '--force-recreate', 'functions'], cwd=root, capture_output=True, timeout=180)
        if step.returncode:
            raise RuntimeError('Functions recreation failed; private output withheld')
        for _ in range(30):
            state = subprocess.run(['docker', 'inspect', '--format', '{{.State.Running}}', 'supabase-edge-functions'], capture_output=True, timeout=10)
            if state.returncode == 0 and state.stdout.strip() == b'true':
                return
            time.sleep(2)
        raise RuntimeError('Functions did not start')

    try:
        for name, path in paths.items():
            write(path, packet['files'][name].encode())
        write(compose, json.dumps(result, indent=2).encode() + b'\n')
        recreate()
        # The Supabase image ships edge-runtime, not a standalone deno binary.
        # Run the exact deployed module in a short-lived container of the same
        # image; expose only a loopback probe that returns a boolean, no tokens.
        probe = folder / 'probe'
        probe.mkdir(mode=0o700)
        (probe / 'worker.mjs').write_bytes(paths['reminder-push/worker.mjs'].read_bytes())
        (probe / 'index.ts').write_text("import {mintFirebaseToken} from './worker.mjs'; Deno.serve(async()=>{try{const t=await mintFirebaseToken(JSON.parse(Deno.env.get('FIREBASE_WORKLOAD_IDENTITY_JSON')));return Response.json({authorized:typeof t==='string'&&t.length>20});}catch{return Response.json({authorized:false},{status:503});}});")
        image = subprocess.run(['docker', 'inspect', '--format', '{{.Config.Image}}', 'supabase-edge-functions'], capture_output=True, check=True, timeout=10).stdout.decode().strip()
        name = 'tabby-firebase-probe-' + secrets.token_hex(4)
        try:
            launch = subprocess.run(['docker', 'run', '-d', '--rm', '--name', name, '-p', '127.0.0.1::9000', '--mount', 'type=bind,source=' + str(probe) + ',target=/probe,readonly', '-e', 'FIREBASE_WORKLOAD_IDENTITY_JSON=' + json.dumps(packet['identity']), '--entrypoint', 'edge-runtime', image, 'start', '--main-service', '/probe'], capture_output=True, timeout=30)
            if launch.returncode:
                raise RuntimeError('Runtime probe launch failed')
            port = subprocess.run(['docker', 'port', name, '9000/tcp'], capture_output=True, check=True, timeout=10).stdout.decode().strip()
            if not port.startswith('127.0.0.1:') or not port[10:].isdigit():
                raise RuntimeError('Runtime probe must be loopback only')
            authorized = False
            for _ in range(15):
                try:
                    with urllib.request.urlopen('http://' + port, timeout=50) as response:
                        authorized = json.load(response).get('authorized') is True
                    break
                except OSError:
                    time.sleep(1)
            if not authorized:
                raise RuntimeError('Deployed runtime federation check failed; private output withheld')
        finally:
            subprocess.run(['docker', 'rm', '-f', name], capture_output=True, timeout=20)
        report.update(outcome='passed', functions_running=True, deployed_runtime_authorization=True, queue_claimed=False, messages_sent=False)
    except Exception as error:
        report['error_type'] = type(error).__name__
        write(compose, raw)
        for name, path in paths.items():
            write(path, base64.b64decode(previous['files'][name]))
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
