# shellcheck shell=bash
# Step 3: Docker, which runs Grafana, InfluxDB and NetAlertX.
# Docker's own installer: https://docs.docker.com/engine/install/

if ! command -v docker >/dev/null; then
  echo "  installing Docker..."
  curl -fsSL https://get.docker.com | sh >/dev/null
fi
if ! docker compose version >/dev/null 2>&1; then
  echo "  installing Docker Compose..."
  apt-get install -y -qq docker-compose-v2 >/dev/null
fi
systemctl enable --now docker >/dev/null 2>&1
