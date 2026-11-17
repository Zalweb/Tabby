#!/usr/bin/env node
'use strict';
const fs = require('node:fs');
const {seal} = require('./azure-full-seal.cjs');
try {
  const config = JSON.parse(fs.readFileSync('.env.azure-smtp.json', 'utf8').replace(/^\uFEFF/, ''));
  const allowed = ['SMTP_HOST','SMTP_PORT','SMTP_USER','SMTP_PASSWORD','SMTP_ADMIN_EMAIL','SMTP_SENDER_NAME','TABBY_TEST_RECIPIENT'];
  if (Object.keys(config).some(key => !allowed.includes(key)) || config.SMTP_HOST !== 'smtp.resend.com' || config.SMTP_PORT !== 587 || config.SMTP_USER !== 'resend' || config.SMTP_ADMIN_EMAIL !== 'onboarding@resend.dev' || !/^re_[a-zA-Z0-9_-]{10,}$/.test(config.SMTP_PASSWORD) || !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(config.TABBY_TEST_RECIPIENT) || Object.values(config).some(value => /[\r\n\0]/.test(String(value)))) throw Error('Complete the private Resend key and test recipient; values withheld.');
  const envelope = seal(fs.readFileSync('.dart_tool/azure-full/migration-public.pem'), Buffer.from(JSON.stringify(config)));
  const p = fs.readFileSync('deploy/azure-full/configure-smtp.py').toString('base64');
  const c = Buffer.from(JSON.stringify(envelope)).toString('base64');
  fs.writeFileSync('.dart_tool/azure-full/run-configure-smtp.sh', `#!/bin/bash\nset -euo pipefail\numask 077\nprintf '%s' '${p}' | base64 -d > /srv/tabby/migration/configure-smtp.py\nprintf '%s' '${c}' | base64 -d > /srv/tabby/migration/smtp-capsule.json\npython3 /srv/tabby/migration/configure-smtp.py\ncd /srv/tabby\ndocker compose up -d --wait --wait-timeout 120 auth >/dev/null 2>&1\nprintf 'TABBY_SMTP_AUTH_SERVICE_HEALTHY\\n'\n`);
  console.log(JSON.stringify({prepared: true, credentials: 'encrypted capsule only', signup: 'disabled', recipient: 'own account only'}));
} catch (error) {console.error(error.message.includes('Complete the private') ? error.message : 'SMTP preparation failed; private values withheld.'); process.exitCode = 1;}
