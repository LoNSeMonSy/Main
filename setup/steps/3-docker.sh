# shellcheck shell=bash
# Step 3: Docker, which runs Grafana, InfluxDB and NetAlertX.
# Docker's own installer: https://docs.docker.com/engine/install/

if ! command -v docker >/dev/null; then
  run "Installing Docker" sh -c 'curl -fsSL https://get.docker.com | sh'
fi
if ! docker compose version >/dev/null 2>&1; then
  run "Installing Docker Compose" apt-get -o DPkg::Lock::Timeout=1800 install -y docker-compose-v2
fi
echo "  docker: $(docker --version | cut -d, -f1)"
systemctl enable --now docker >/dev/null 2>&1
