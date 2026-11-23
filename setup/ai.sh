#!/usr/bin/env bash
# AI explanations of alarms (optional).
#   sudo ./setup/ai.sh on       turn it on (or set it up again)
#   sudo ./setup/ai.sh off      turn it off; alarms still email as before
#   sudo ./setup/ai.sh status   is it running, and can it reach the model?
#
# How it works: Grafana sends each Medium or worse alarm to n8n (a workflow tool).
# The workflow (appliance/n8n/alert-explainer.json) looks up the Wazuh events, asks
# the model (Ollama) for a short explanation, emails it and saves it for the Alarms
# page. The AI only explains; it never blocks or changes anything.
#
# The model runs on this server, or on another computer running Ollama (OLLAMA_URL
# in appliance/.env, e.g. http://192.168.1.60:11434). Alarm data stays on your network.
# shellcheck source-path=SCRIPTDIR/..
set -euo pipefail
cd "$(dirname "$0")/.." || exit 1
if [ "$(id -u)" != 0 ]; then echo "  Run it with sudo."; exit 1; fi
source setup/steps/helpers.sh
if [ "${1:-}" != download ]; then only_one ai "lsmsy ai is already running. Try again when it's done."; fi
POLICIES=appliance/grafana/provisioning/alerting/policies.yaml
compose() { docker compose -f appliance/docker-compose.yml --profile ai "$@"; }
reload_alarms() {
  curl -s -m 15 -o /dev/null -u "admin:$(get GRAFANA_ADMIN_PASSWORD)" \
    -X POST http://localhost:3000/api/admin/provisioning/alerting/reload || true
}

url=$(get OLLAMA_URL)
model=$(get OLLAMA_MODEL)
if [ -z "$model" ]; then
  # On this server: the small model under 12 GB of memory, the better one above.
  if [ -z "$url" ] && [ "$(awk '/MemTotal/{print int($2/1048576)}' /proc/meminfo)" -lt 12 ]; then
    model=gemma3:1b
  else
    model=gemma3:4b
  fi
fi

on() {
  [ -n "$(get N8N_ENCRYPTION_KEY)" ] || set_env N8N_ENCRYPTION_KEY "$(openssl rand -hex 24)"
  set_env OLLAMA_MODEL "$model"

  wait_download
  if [ -z "$url" ]; then
    run "Downloading the AI workflow tool (n8n)" compose pull --quiet n8n
    run "Downloading the AI engine (Ollama, a big download, often 10-15 minutes)" compose pull --quiet ollama
    run "Starting the AI" compose up -d n8n ollama
    run "Downloading the AI model ($model)" docker exec ollama ollama pull "$model"
  else
    run "Downloading the AI workflow tool (n8n)" compose pull --quiet n8n
    run "Starting the AI workflow (n8n)" compose up -d n8n
    # Download the model to that computer, unless it already has it.
    if ! curl -sf -m 10 "$url/api/tags" | grep -q "\"$model\""; then
      if ! run "Downloading the AI model to $url ($model)" \
        curl -sf -m 1800 "$url/api/pull" -d "{\"model\":\"$model\",\"stream\":false}"; then
        echo "  Couldn't reach Ollama at $url. Check that it's running and listening on the network."
      fi
    fi
  fi

  # n8n gets the email login (from .env) and the workflow, then turns it on.
  run "Waiting for the AI workflow to start" timeout 120 \
    bash -c "until curl -sf -m 3 http://127.0.0.1:5678/healthz; do sleep 2; done" || true
  local host port
  host=$(get SMTP_HOST); port=${host##*:}; host=${host%%:*}; [ "$port" != "$host" ] || port=587
  # Written by n8n's own user, so it can read it.
  docker exec -u root n8n rm -f /tmp/smtp.json
  jq -n --arg u "$(get SMTP_USER)" --arg p "$(get SMTP_PASSWORD)" --arg h "$host" --argjson port "$port" \
    '[{id:"lonsemonsySmtp01", name:"LoNSeMonSy email", type:"smtp", data:{user:$u, password:$p, host:$h, port:$port, secure:false}}]' |
    docker exec -i n8n sh -c 'umask 077; cat > /tmp/smtp.json'
  run "Loading the AI workflow" docker exec n8n sh -c 'n8n import:credentials --input=/tmp/smtp.json && rm -f /tmp/smtp.json &&
    n8n import:workflow --input=/lonsemonsy-n8n/alert-explainer.json && n8n publish:workflow --id=lonsemonsyAlrtEx'
  docker restart n8n >/dev/null

  # Grafana also sends Medium or worse alarms to the workflow. Email stays the same.
  cp appliance/n8n/policies-with-ai.yaml "$POLICIES"
  reload_alarms
  set_env AI_ENABLED true
  echo "  AI explanations: on ($model${url:+ at $url})"
}

off() {
  git -c safe.directory="$PWD" show HEAD:"$POLICIES" > "$POLICIES"
  reload_alarms
  compose stop n8n ollama >/dev/null 2>&1 || true
  set_env AI_ENABLED false
  echo "  AI explanations: off. Alarms still email as before."
}

status() {
  echo "  AI explanations: $( [ "$(get AI_ENABLED)" = true ] && echo on || echo off)"
  echo "  workflow (n8n):  $(docker inspect -f '{{.State.Status}}' n8n 2>/dev/null || echo 'not installed')"
  echo "  model:           $model at ${url:-this server}"
  if docker exec n8n wget -qO- "${url:-http://ollama:11434}/api/tags" 2>/dev/null | grep -q "\"$model\""; then
    echo "  model ready:     yes"
  else
    echo "  model ready:     no"
  fi
}

# download: get the AI's images in the background during setup, so step 10 waits less.
download() {
  [ "$(get AI_ENABLED)" = true ] || return 0
  local images=(n8n); if [ -z "$url" ]; then images+=(ollama); fi
  setsid bash -c 'docker compose -f appliance/docker-compose.yml --profile ai pull --quiet "$@"' _ "${images[@]}" </dev/null >/var/log/lonsemonsy-ai-download.log 2>&1 &
  echo $! > /run/lonsemonsy-ai-download.pid
}
wait_download() {
  local pid; pid=$(cat /run/lonsemonsy-ai-download.pid 2>/dev/null || true)
  if [ -n "$pid" ] && grep -qs compose "/proc/$pid/cmdline"; then
    run "Finishing the AI download that started earlier" bash -c "while kill -0 $pid 2>/dev/null; do sleep 2; done"
  fi
  rm -f /run/lonsemonsy-ai-download.pid
}

case "${1:-}" in
  download) download ;;
  on) on ;;
  off) off ;;
  status) status ;;
  *) echo "  usage: lsmsy ai on | off | status"; exit 1 ;;
esac
