# Linting

[![Lint](https://github.com/LoNSeMonSy/Main/actions/workflows/lint.yml/badge.svg)](https://github.com/LoNSeMonSy/Main/actions/workflows/lint.yml)

A lint checker reads the code and points out mistakes and risky habits *without running it*.

## 1. The lint checker for our language

LoNSeMonSy is mostly **Bash** (the installer and helper scripts) plus YAML and JSON config, so we use one checker per kind of file:

| Files | Checker | What it catches |
|---|---|---|
| `*.sh` (the setup steps and helper scripts) | [ShellCheck](https://www.shellcheck.net) | unquoted variables, `cd` without a fallback, unused variables, logic that doesn't do what it looks like |
| `*.yml`, `*.yaml` (Docker Compose, Grafana, the workflow) | [yamllint](https://yamllint.readthedocs.io) | broken indentation, duplicate keys, bad syntax. Rules in [`yamllint.yml`](yamllint.yml) |
| `*.json` (Grafana dashboards) | `python3 -m json.tool` | invalid JSON that would stop a dashboard from loading |

## 2. Script to run locally

```bash
sudo apt install shellcheck yamllint   # once
./lint/lint.sh
```

[`lint.sh`](lint.sh) runs all three checks on every file in the repo and exits with an error if any fail.

## 3. Workflow action on GitHub

[`.github/workflows/lint.yml`](../.github/workflows/lint.yml) runs the same `lint/lint.sh` on GitHub's servers on every push and pull request, and from the **Run workflow** button in the Actions tab (pick a branch, e.g. staging). Each commit then shows a green check or a red X, and the details are under the repo's **Actions** tab.

## 4. Results

**First run (2026-10-24)**, ShellCheck found 3 problems. YAML and JSON passed:

```
setup/check-update.sh:6:1: warning: Use 'cd ... || exit' or 'cd ... || return' in case cd fails. [SC2164]
setup/setup.sh:226:15: note: Note that A && B || C is not if-then-else. C may run when A is true. [SC2015]
setup/setup.sh:358:3: warning: i appears unused. Verify use (or export if used externally). [SC2034]
```

**What we changed:**

| Finding | Fix |
|---|---|
| SC2164 `cd` without a fallback | `cd ... \|\| exit 1`, so the script stops instead of running in the wrong folder |
| SC2015 `A && B \|\| C` | rewritten as a plain `if ... then ... fi` |
| SC2034 unused loop variable | renamed to `_`, the usual name for "not used" |

**Now:** all checks pass, locally and on GitHub (see the badge above and the Actions tab).
