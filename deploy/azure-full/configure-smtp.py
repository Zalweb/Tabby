"""Verify SMTP STARTTLS/authentication and configure GoTrue without sending mail."""
import base64
import argparse
import json
import os
import smtplib
import ssl
from email.message import EmailMessage
from pathlib import Path
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import padding
from cryptography.hazmat.primitives.ciphers.aead import AESGCM

os.umask(0o077)
parser = argparse.ArgumentParser()
parser.add_argument('--send-test', action='store_true')
args = parser.parse_args()
root = Path('/srv/tabby/migration')
private = serialization.load_pem_private_key(Path('/srv/tabby/migration-private.pem').read_bytes(), password=None)
envelope = json.loads((root / 'smtp-capsule.json').read_text())
key = private.decrypt(base64.b64decode(envelope['wrappedKey']), padding.OAEP(mgf=padding.MGF1(hashes.SHA256()), algorithm=hashes.SHA256(), label=None))
config = json.loads(AESGCM(key).decrypt(base64.b64decode(envelope['iv']), base64.b64decode(envelope['ciphertext']) + base64.b64decode(envelope['tag']), None))
try:
    with smtplib.SMTP(config['SMTP_HOST'], config['SMTP_PORT'], timeout=30) as smtp:
        smtp.ehlo()
        smtp.starttls(context=ssl.create_default_context())
        smtp.ehlo()
        smtp.login(config['SMTP_USER'], config['SMTP_PASSWORD'])
        smtp.noop()
        if args.send_test:
            message = EmailMessage()
            message['From'] = 'Tabby Test <' + config['SMTP_ADMIN_EMAIL'] + '>'
            message['To'] = config['TABBY_TEST_RECIPIENT']
            message['Subject'] = 'Tabby Azure email test'
            message.set_content('The Tabby Azure backend can connect to its email provider. This is the test message requested for your own email address. No account or password was changed.')
            refused = smtp.send_message(message)
            if refused:
                raise RuntimeError('Test recipient was refused.')
except Exception as error:
    print(json.dumps({'stage': 'smtp-connection', 'outcome': 'failed', 'error_type': type(error).__name__}), flush=True)
    raise SystemExit(2)
path = Path('/srv/tabby/docker-compose.tabby.yml')
compose = json.loads(path.read_text())
auth = compose['services']['auth']['environment']
for name in ['HOST', 'PORT', 'USER', 'PASS', 'ADMIN_EMAIL', 'SENDER_NAME']:
    field = 'SMTP_PASSWORD' if name == 'PASS' else 'SMTP_' + name
    auth['GOTRUE_SMTP_' + name] = str(config[field]).replace('$', '$$')
path.write_text(json.dumps(compose, indent=2))
print(json.dumps({'stage': 'smtp-config', 'outcome': 'passed', 'starttls_and_auth': True, 'signup': 'still disabled', 'email_delivery': 'test accepted by SMTP; inbox arrival unverified' if args.send_test else 'unverified; no message sent', 'recipient_scope': 'Resend account owner only'}), flush=True)
