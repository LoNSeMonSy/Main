#!/usr/bin/env bash
# Checks the code for mistakes without running it ("linting"):
#   ShellCheck  the shell scripts (*.sh)          https://www.shellcheck.net
#   yamllint    the YAML config (*.yml, *.yaml)   https://yamllint.readthedocs.io
#   python3     the Grafana dashboards are valid JSON
#
#   ./lint/lint.sh   run it before you push
# GitHub runs the same script on every push (.github/workflows/lint.yml).
# Install the tools once:  sudo apt install shellcheck yamllint
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1   # the main folder
for tool in shellcheck yamllint python3; do
  command -v "$tool" >/dev/null || { echo "Missing $tool. Install it with: sudo apt install shellcheck yamllint"; exit 2; }
done
failed=0

echo "== ShellCheck: shell scripts"
# setup/steps/ are checked through setup/setup.sh, which runs them in order (-x).
mapfile -t files < <(git ls-files '*.sh' ':!setup/steps/*')
if shellcheck -x "${files[@]}"; then echo "   ${#files[@]} scripts (and setup's steps), no problems"; else failed=1; fi

echo "== yamllint: YAML config (rules in lint/yamllint.yml)"
mapfile -t files < <(git ls-files '*.yml' '*.yaml')
if yamllint -c lint/yamllint.yml "${files[@]}"; then echo "   ${#files[@]} files, no problems"; else failed=1; fi

echo "== JSON: Grafana dashboards"
mapfile -t files < <(git ls-files '*.json')
bad=0
for f in "${files[@]}"; do
  python3 -m json.tool "$f" >/dev/null 2>&1 || { echo "   not valid JSON: $f"; bad=1; failed=1; }
done
[ "$bad" = 0 ] && echo "   ${#files[@]} files, no problems"

echo
if [ "$failed" = 0 ]; then echo "All checks passed."; else echo "Some checks failed (see above)."; fi
exit "$failed"
