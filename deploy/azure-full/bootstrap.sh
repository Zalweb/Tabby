#!/usr/bin/env bash
set -euo pipefail
umask 077
install -d -m 0700 /srv/tabby
if test -f /srv/tabby/.bootstrap-complete; then
  echo 'Tabby bootstrap was already completed; preserving existing data and secrets.'
  exit 0
fi
systemctl enable --now docker
if ! test -d /opt/tabby-upstream/.git; then
  git clone --depth 1 --filter=blob:none --sparse --branch self-hosted/v0.8.4 \
    https://github.com/supabase/supabase.git /opt/tabby-upstream
fi
git -C /opt/tabby-upstream sparse-checkout set docker
test "$(git -C /opt/tabby-upstream rev-parse HEAD)" = '189adda99d1b56da55fc5a6ee3f849354aaea92a'
if ! test -f /srv/tabby/.env; then
  cp -a /opt/tabby-upstream/docker/. /srv/tabby/
  python3 /opt/tabby/generate-env.py
fi
cp /opt/tabby/docker-compose.private.yml /srv/tabby/docker-compose.private.yml
if ! test -f /swapfile; then
  fallocate -l 2G /swapfile
  chmod 0600 /swapfile
  mkswap /swapfile >/dev/null
  swapon /swapfile
  printf '/swapfile none swap sw 0 0\n' >> /etc/fstab
fi
if ! test -f /srv/tabby/migration-private.pem; then
  openssl genpkey -algorithm RSA -pkeyopt rsa_keygen_bits:3072 \
    -out /srv/tabby/migration-private.pem 2>/dev/null
  openssl pkey -in /srv/tabby/migration-private.pem -pubout \
    -out /srv/tabby/migration-public.pem 2>/dev/null
fi
cd /srv/tabby
# Reach this VM's valid HTTPS hostname locally, avoiding a public-IP hairpin.
hostname="$(cat /etc/tabby-hostname)"
if ! grep -Fq "127.0.0.1 ${hostname} # tabby-local-api" /etc/hosts; then
  printf '127.0.0.1 %s # tabby-local-api\n' "$hostname" >> /etc/hosts
fi
docker compose pull --quiet
docker compose up -d --wait --wait-timeout 180 db
bash /opt/tabby/initialize-platform.sh
docker compose up -d --wait --wait-timeout 900
touch .bootstrap-complete
echo 'Tabby destination stack started. Production import and acceptance are still pending.'
