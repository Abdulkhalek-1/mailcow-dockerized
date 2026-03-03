#!/usr/bin/env bash
set -euo pipefail

# Initial server setup for mailcow behind Traefik.
# Run this ONCE on the server to provision mailcow.
#
# Prerequisites:
#   - Docker >= 24 installed
#   - Traefik running via server-gateway with 'gateway' network
#   - DNS records configured (A, MX, SPF, DMARC)
#   - Firewall ports open (25, 465, 587, 993, 995, 4190)
#
# Usage: ./scripts/server-setup.sh

DEPLOY_PATH="/opt/mailcow"
MAILCOW_HOSTNAME="mail.abdulkhalek.dev"
TIMEZONE="UTC"

echo "==> Mailcow Server Setup"
echo "    Deploy path: $DEPLOY_PATH"
echo "    Hostname: $MAILCOW_HOSTNAME"
echo ""

# Check Docker
if ! docker compose version &>/dev/null; then
  echo "ERROR: Docker Compose not found. Install Docker first."
  exit 1
fi

DOCKER_VERSION=$(docker version --format '{{.Server.Version}}' | cut -d. -f1)
if [ "$DOCKER_VERSION" -lt 24 ]; then
  echo "ERROR: Docker >= 24 required (found $DOCKER_VERSION)."
  exit 1
fi

# Check gateway network
if ! docker network inspect gateway &>/dev/null; then
  echo "ERROR: 'gateway' network not found. Start Traefik first."
  exit 1
fi

# Check if already set up
if [ -f "$DEPLOY_PATH/mailcow.conf" ]; then
  echo "==> mailcow.conf already exists at $DEPLOY_PATH."
  read -r -p "    Overwrite? [y/N] " response
  case $response in
    [yY]) echo "    Proceeding..." ;;
    *) echo "    Aborting."; exit 0 ;;
  esac
fi

# Create .env symlink if missing
cd "$DEPLOY_PATH"
if [ ! -L .env ]; then
  ln -sf mailcow.conf .env
  echo "==> Created .env symlink."
fi

# Run generate_config.sh if no mailcow.conf
if [ ! -f mailcow.conf ]; then
  echo "==> Running generate_config.sh..."
  echo "    When prompted:"
  echo "    - Hostname: $MAILCOW_HOSTNAME"
  echo "    - Timezone: $TIMEZONE"
  echo "    - Branch: 1 (master)"
  echo ""
  ./generate_config.sh

  echo ""
  echo "==> Applying behind-Traefik configuration..."

  # Bind HTTP/HTTPS to localhost (Traefik handles public traffic)
  sed -i 's/^HTTP_PORT=.*/HTTP_PORT=8080/' mailcow.conf
  sed -i 's/^HTTP_BIND=.*/HTTP_BIND=127.0.0.1/' mailcow.conf
  sed -i 's/^HTTPS_PORT=.*/HTTPS_PORT=8443/' mailcow.conf
  sed -i 's/^HTTPS_BIND=.*/HTTPS_BIND=127.0.0.1/' mailcow.conf

  # Disable HTTP→HTTPS redirect (Traefik handles this)
  sed -i 's/^HTTP_REDIRECT=.*/HTTP_REDIRECT=n/' mailcow.conf

  # Disable mailcow's Let's Encrypt (Traefik + certdumper handles certs)
  sed -i 's/^SKIP_LETS_ENCRYPT=.*/SKIP_LETS_ENCRYPT=y/' mailcow.conf
  sed -i 's/^AUTODISCOVER_SAN=.*/AUTODISCOVER_SAN=n/' mailcow.conf

  # Add autodiscover/autoconfig as server names
  sed -i "s/^ADDITIONAL_SERVER_NAMES=.*/ADDITIONAL_SERVER_NAMES=autodiscover.abdulkhalek.dev,autoconfig.abdulkhalek.dev/" mailcow.conf

  chmod 600 mailcow.conf
  echo "==> mailcow.conf configured."
else
  echo "==> mailcow.conf already exists. Skipping generation."
fi

# Pull and start
echo ""
echo "==> Pulling Docker images (this may take a while)..."
docker compose pull

echo "==> Starting mailcow..."
docker compose up -d

echo ""
echo "==> Waiting for services to start..."
sleep 10

echo "==> Container status:"
docker compose ps

echo ""
echo "============================================"
echo "  Mailcow is starting!"
echo ""
echo "  Web UI: https://$MAILCOW_HOSTNAME"
echo "  Login:  admin / moohoo"
echo "  (CHANGE THE PASSWORD IMMEDIATELY)"
echo ""
echo "  ClamAV may take 5-10 minutes to start"
echo "  on first boot (downloading virus defs)."
echo ""
echo "  Next steps:"
echo "  1. Change admin password"
echo "  2. Add domain: abdulkhalek.dev"
echo "  3. Generate DKIM key -> add DNS record"
echo "  4. Create mailbox(es)"
echo "  5. Test with mail-tester.com"
echo "============================================"
