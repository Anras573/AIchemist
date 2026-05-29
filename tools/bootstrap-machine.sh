#!/usr/bin/env bash
set -euo pipefail

PLUGIN_NAME="aichemist"
MARKITDOWN_IMAGE="mcp/markitdown@sha256:1cef3bf502503310ed0884441874ccf6cdaac20136dc1179797fa048269dc4cb"
MEMPALACE_HOME="${HOME}/.mempalace"
OBSIDIAN_MAC_PATH="/Applications/Obsidian.app/Contents/MacOS/obsidian"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BREWFILE_PATH="${REPO_ROOT}/Brewfile"
MISSING_COUNT=0

log() { echo "==> $*"; }
ok() { echo "READY: $*"; }
warn() { echo "WARN: $*" >&2; }
die() { echo "ERROR: $*" >&2; exit 1; }

usage() {
  cat <<'EOF'
Usage: tools/bootstrap-machine.sh [install|doctor]

Commands:
  install   Install machine dependencies, plugin tool dependencies, and plugin registrations (default)
  doctor    Validate dependency + plugin health and print actionable fixes
EOF
}

require_macos() {
  [[ "$(uname -s)" == "Darwin" ]] || die "This bootstrap script currently supports macOS only."
}

require_brew() {
  if ! command -v brew >/dev/null 2>&1; then
    die "Homebrew is required. Install it from https://brew.sh and rerun this script."
  fi
}

mark_missing() {
  local label="$1"
  local action="$2"
  local required="${3:-true}"

  echo "MISSING: ${label}"
  echo "  ACTION: ${action}"
  if [[ "${required}" == "true" ]]; then
    MISSING_COUNT=$((MISSING_COUNT + 1))
  fi
}

check_cmd() {
  local cmd="$1"
  local action="$2"
  local required="${3:-true}"

  if command -v "${cmd}" >/dev/null 2>&1; then
    ok "${cmd}"
  else
    mark_missing "${cmd}" "${action}" "${required}"
  fi
}

check_env() {
  local name="$1"
  local action="$2"
  local required="${3:-true}"

  if [[ -n "${!name:-}" ]]; then
    ok "env ${name}"
  else
    mark_missing "env ${name}" "${action}" "${required}"
  fi
}

install_brew_dependencies() {
  [[ -f "${BREWFILE_PATH}" ]] || die "Brewfile not found at ${BREWFILE_PATH}"
  log "Installing Homebrew dependencies from Brewfile"
  brew bundle --file "${BREWFILE_PATH}"
}

install_npm_tools() {
  log "Installing npm global tools"
  npm install -g @playwright/cli@latest @pnp/cli-microsoft365
}

install_mempalace_tool() {
  log "Installing/upgrading mempalace via uv tool"
  if uv tool list 2>/dev/null | grep -q "mempalace"; then
    uv tool upgrade mempalace
  else
    uv tool install mempalace
  fi
}

init_mempalace() {
  if [[ -d "${MEMPALACE_HOME}" ]]; then
    ok "mempalace initialized (${MEMPALACE_HOME})"
    return
  fi

  command -v uv >/dev/null 2>&1 || die "'uv' is required to initialize mempalace."
  log "Initializing mempalace at ${MEMPALACE_HOME}"
  uv tool run --from mempalace mempalace init "${MEMPALACE_HOME}"
}

pull_markitdown_image() {
  if ! docker info >/dev/null 2>&1; then
    warn "Docker daemon is not running; skipping markitdown image pull for now."
    return
  fi

  log "Pulling markitdown image"
  docker pull "${MARKITDOWN_IMAGE}"
}

install_plugin_claude() {
  if ! command -v claude >/dev/null 2>&1; then
    warn "'claude' CLI not found; skipping Claude plugin registration."
    return
  fi

  log "Installing ${PLUGIN_NAME} for Claude Code from local path"
  if ! claude plugin install "${REPO_ROOT}"; then
    warn "Claude plugin install returned non-zero. Verify with: claude plugin list"
  fi
}

install_plugin_copilot() {
  if ! command -v copilot >/dev/null 2>&1; then
    warn "'copilot' CLI not found; skipping Copilot plugin registration."
    return
  fi

  log "Installing ${PLUGIN_NAME} for GitHub Copilot CLI from local path"
  if ! copilot plugin install "${REPO_ROOT}"; then
    warn "Copilot plugin install returned non-zero. Verify with: copilot plugin list"
  fi
}

doctor() {
  require_macos
  MISSING_COUNT=0

  echo "AIchemist machine doctor"
  echo "Repo: ${REPO_ROOT}"
  echo

  check_cmd "brew" "Install Homebrew: https://brew.sh"
  check_cmd "jq" "brew install jq"
  check_cmd "python3" "brew install python"
  check_cmd "node" "brew install node"
  check_cmd "npm" "brew install node"
  check_cmd "uv" "brew install uv"
  check_cmd "docker" "brew install --cask docker-desktop"
  check_cmd "lizard" "brew install lizard-analyzer"
  check_cmd "bd" "brew install beads"
  check_cmd "psql" "brew install postgresql"
  check_cmd "m365" "npm install -g @pnp/cli-microsoft365"
  check_cmd "playwright-cli" "npm install -g @playwright/cli@latest"
  check_cmd "mempalace" "uv tool install mempalace"
  check_cmd "claude" "Install Claude Code CLI first, then rerun bootstrap."
  check_cmd "copilot" "Install GitHub Copilot CLI first, then rerun bootstrap."

  if [[ -x "${OBSIDIAN_MAC_PATH}" ]] || command -v obsidian >/dev/null 2>&1; then
    ok "obsidian"
  else
    mark_missing "obsidian" "brew install --cask obsidian" "false"
  fi

  check_env "MSGRAPH_APP_ID" "export MSGRAPH_APP_ID=<your-azure-app-id>" "false"
  check_env "MSGRAPH_TENANT_ID" "export MSGRAPH_TENANT_ID=<your-azure-tenant-id>" "false"
  check_env "POSTGRES_URL" "export POSTGRES_URL='postgresql://user:password@host:5432/database'" "false"

  if [[ -d "${MEMPALACE_HOME}" ]]; then
    ok "mempalace home (${MEMPALACE_HOME})"
  else
    mark_missing "mempalace home (${MEMPALACE_HOME})" "mempalace init ${MEMPALACE_HOME}"
  fi

  if command -v docker >/dev/null 2>&1; then
    if docker info >/dev/null 2>&1; then
      ok "docker daemon"
      if docker image inspect "${MARKITDOWN_IMAGE}" >/dev/null 2>&1; then
        ok "markitdown image"
      else
        mark_missing "markitdown image" "docker pull ${MARKITDOWN_IMAGE}"
      fi
    else
      mark_missing "docker daemon" "Open Docker Desktop and rerun doctor."
    fi
  fi

  if command -v claude >/dev/null 2>&1; then
    if claude plugin list 2>/dev/null | grep -qi "${PLUGIN_NAME}"; then
      ok "claude plugin ${PLUGIN_NAME}"
    else
      mark_missing "claude plugin ${PLUGIN_NAME}" "claude plugin install ${REPO_ROOT}"
    fi
  fi

  if command -v copilot >/dev/null 2>&1; then
    if copilot plugin list 2>/dev/null | grep -qi "${PLUGIN_NAME}"; then
      ok "copilot plugin ${PLUGIN_NAME}"
    else
      mark_missing "copilot plugin ${PLUGIN_NAME}" "copilot plugin install ${REPO_ROOT}"
    fi
  fi

  echo
  if [[ "${MISSING_COUNT}" -eq 0 ]]; then
    echo "Doctor result: healthy"
    return 0
  fi

  echo "Doctor result: ${MISSING_COUNT} required item(s) need attention."
  return 1
}

install() {
  require_macos
  require_brew
  install_brew_dependencies
  install_npm_tools
  install_mempalace_tool
  init_mempalace
  pull_markitdown_image
  install_plugin_claude
  install_plugin_copilot
  doctor
}

main() {
  local command="${1:-install}"

  case "${command}" in
    install)
      install
      ;;
    doctor)
      doctor
      ;;
    -h|--help|help)
      usage
      ;;
    *)
      usage
      exit 1
      ;;
  esac
}

main "${@}"
