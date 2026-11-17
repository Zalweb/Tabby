#!/usr/bin/env bash
set -u
cloud-init status --long || true
if test -f /srv/tabby/.bootstrap-complete; then echo TABBY_BOOTSTRAP_COMPLETE; fi
if test -f /srv/tabby/.env; then echo TABBY_ENV_PRESENT; fi
if test -d /srv/tabby; then
  cd /srv/tabby
  docker compose ps --format '{{.Name}} {{.State}} {{.Health}}' 2>/dev/null || true
fi
tail -n 16 /var/log/cloud-init-output.log 2>/dev/null || true
