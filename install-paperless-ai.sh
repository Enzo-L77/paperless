#!/usr/bin/env bash
# ╔══════════════════════════════════════════════════════════════╗
# ║  Paperless Overconfigured — paperless-ai Add-On Installer   ║
# ║                                                              ║
# ║  Adds clusterzx/paperless-ai to an existing Paperless       ║
# ║  Overconfigured installation.                               ║
# ║                                                              ║
# ║  Usage:                                                      ║
# ║    bash install-paperless-ai.sh                             ║
# ║                                                              ║
# ║  Requirements:                                               ║
# ║    - Paperless Overconfigured already installed             ║
# ║    - Docker + Docker Compose available                      ║
# ╚══════════════════════════════════════════════════════════════╝

set -euo pipefail

# ── Colors ────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m'

# ── Helpers ───────────────────────────────────────────────────
info()    { echo -e "${BLUE}[INFO]${NC} $1"; }
success() { echo -e "${GREEN}[OK]${NC} $1"; }
warn()    { echo -e "${YELLOW}[WARN]${NC} $1"; }
error()   { echo -e "${RED}[ERROR]${NC} $1"; }
fatal()   { echo -e "${RED}[FATAL]${NC} $1"; exit 1; }
step()    { echo -e "\n${CYAN}${BOLD}$1${NC}"; }
prompt()  { echo -ne "${BOLD}$1${NC}"; }

ask() {
    local var="$1" message="$2" default="$3"
    if [ -n "$default" ]; then
        prompt "$message [$default]: "
        read -r input
        eval "$var=\"${input:-$default}\""
    else
        prompt "$message: "
        read -r input
        eval "$var=\"$input\""
    fi
}

ask_secret() {
    local var="$1" message="$2"
    prompt "$message: "
    read -rs input
    echo
    eval "$var=\"$input\""
}

# ── Banner ────────────────────────────────────────────────────
echo ""
echo -e "${CYAN}${BOLD}"
echo "  ╔═══════════════════════════════════════════════╗"
echo "  ║        paperless-ai Add-On Installer          ║"
echo "  ║   AI-powered document analysis for Paperless  ║"
echo "  ╚═══════════════════════════════════════════════╝"
echo -e "${NC}"
echo -e "${DIM}  This script adds clusterzx/paperless-ai to your"
echo -e "  existing Paperless Overconfigured installation.${NC}"
echo ""

# ── Locate existing installation ─────────────────────────────
step "[1/5] Locate Paperless Installation"

INSTALL_DIR=""
DEFAULT_DIR="/opt/paperless"

if [ -f "$DEFAULT_DIR/.env" ]; then
    INSTALL_DIR="$DEFAULT_DIR"
    success "Found installation at $INSTALL_DIR"
else
    prompt "Paperless installation directory [$DEFAULT_DIR]: "
    read -r input
    INSTALL_DIR="${input:-$DEFAULT_DIR}"
fi

[ -f "$INSTALL_DIR/.env" ] || fatal "No .env found at $INSTALL_DIR — is Paperless installed there?"
[ -f "$INSTALL_DIR/docker-compose.yml" ] || fatal "No docker-compose.yml found at $INSTALL_DIR"

# shellcheck source=/dev/null
source "$INSTALL_DIR/.env"

success "Configuration loaded from $INSTALL_DIR/.env"

# ── Check if paperless-ai profile already active ──────────────
if echo "${COMPOSE_PROFILES:-}" | grep -q "paperless-ai"; then
    warn "paperless-ai profile is already active in COMPOSE_PROFILES"
    prompt "Re-configure anyway? (y/N): "
    read -r reconfigure
    if [[ ! "$reconfigure" =~ ^[Yy] ]]; then
        info "Aborted. No changes made."
        exit 0
    fi
fi

# ── Check for PAPERLESS_API_TOKEN ─────────────────────────────
step "[2/5] Paperless API Token"

if [ -z "${PAPERLESS_API_TOKEN:-}" ]; then
    echo ""
    warn "PAPERLESS_API_TOKEN is not set in $INSTALL_DIR/.env"
    echo ""
    echo -e "${DIM}paperless-ai needs an API token to connect to Paperless-NGX."
    echo -e "To generate one:${NC}"
    echo -e "  ${CYAN}1)${NC} Open Paperless web UI"
    echo -e "  ${CYAN}2)${NC} Go to: Settings → API Tokens"
    echo -e "  ${CYAN}3)${NC} Create a new token and copy it here"
    echo ""
    ask_secret PAPERLESS_API_TOKEN "Paste your Paperless API token (or leave blank to set later)"
else
    success "PAPERLESS_API_TOKEN already set"
    PAPERLESS_API_TOKEN="${PAPERLESS_API_TOKEN}"
fi

# ── AI Provider ───────────────────────────────────────────────
step "[3/5] AI Provider"
echo ""
echo -e "${DIM}paperless-ai uses an LLM to analyze, tag and title your documents.${NC}"
echo ""
echo -e "  ${CYAN}1)${NC} ${GREEN}OpenAI (GPT-4o) — recommended${NC}"
echo -e "     ${DIM}High quality. Get key: https://platform.openai.com/api-keys${NC}"
echo ""
echo -e "  ${CYAN}2)${NC} Ollama (local LLM)"
echo -e "     ${DIM}Fully private. Requires Ollama running on your network.${NC}"
echo ""
prompt "Enter choice [1-2]: "
read -r AI_CHOICE

PAPERLESS_AI_PROVIDER=""
PAPERLESS_AI_OPENAI_API_KEY=""
PAPERLESS_AI_OPENAI_MODEL=""
PAPERLESS_AI_OLLAMA_URL=""
PAPERLESS_AI_OLLAMA_MODEL=""

case "$AI_CHOICE" in
    1)
        PAPERLESS_AI_PROVIDER="openai"
        ask_secret PAPERLESS_AI_OPENAI_API_KEY "OpenAI API key"
        ask PAPERLESS_AI_OPENAI_MODEL "Model name" "gpt-4o"
        ;;
    2)
        PAPERLESS_AI_PROVIDER="ollama"
        ask PAPERLESS_AI_OLLAMA_URL "Ollama URL" "http://host.docker.internal:11434"
        ask PAPERLESS_AI_OLLAMA_MODEL "Model name" "llama3"
        ;;
    *)
        fatal "Invalid choice. Please run the script again and choose 1 or 2."
        ;;
esac

success "AI provider: $PAPERLESS_AI_PROVIDER"

# ── Scan & Tag Settings ───────────────────────────────────────
step "[4/5] Scan & Tag Settings"
echo ""

ask PAPERLESS_AI_SCAN_INTERVAL "Scan interval in minutes" "30"
echo ""

echo -e "${DIM}paperless-ai can add a tag to processed documents for easy filtering.${NC}"
prompt "Add tag to processed documents? (Y/n): "
read -r add_tag_input
if [[ "$add_tag_input" =~ ^[Nn] ]]; then
    PAPERLESS_AI_ADD_TAG="false"
    PAPERLESS_AI_TAG_NAME=""
else
    PAPERLESS_AI_ADD_TAG="true"
    ask PAPERLESS_AI_TAG_NAME "Tag name" "ai-processed"
fi

echo ""
echo -e "${DIM}Process already-existing documents on first start?${NC}"
prompt "Process existing documents? (y/N): "
read -r process_existing
if [[ "$process_existing" =~ ^[Yy] ]]; then
    PAPERLESS_AI_PROCESS_PREDEFINED="true"
else
    PAPERLESS_AI_PROCESS_PREDEFINED="false"
fi

# ── Apply changes ─────────────────────────────────────────────
step "[5/5] Applying Configuration"

# Update .env — add paperless-ai variables
# Remove any existing paperless-ai block first
if grep -q "PAPERLESS_AI_PROVIDER" "$INSTALL_DIR/.env"; then
    warn "Updating existing paperless-ai configuration..."
    # Use a temp file to rewrite the env without the old paperless-ai block
    TMPENV=$(mktemp)
    awk '
        /^# ── paperless-ai/,/^PAPERLESS_AI_PROCESS_PREDEFINED/ { next }
        { print }
    ' "$INSTALL_DIR/.env" > "$TMPENV"
    mv "$TMPENV" "$INSTALL_DIR/.env"
fi

# Update or set PAPERLESS_API_TOKEN
if grep -q "^PAPERLESS_API_TOKEN=" "$INSTALL_DIR/.env"; then
    sed -i "s|^PAPERLESS_API_TOKEN=.*|PAPERLESS_API_TOKEN=$PAPERLESS_API_TOKEN|" "$INSTALL_DIR/.env"
else
    echo "PAPERLESS_API_TOKEN=$PAPERLESS_API_TOKEN" >> "$INSTALL_DIR/.env"
fi

# Append paperless-ai block
cat >> "$INSTALL_DIR/.env" << ENVEOF

# ── paperless-ai ──
PAPERLESS_AI_PROVIDER=$PAPERLESS_AI_PROVIDER
PAPERLESS_AI_OPENAI_API_KEY=$PAPERLESS_AI_OPENAI_API_KEY
PAPERLESS_AI_OPENAI_MODEL=$PAPERLESS_AI_OPENAI_MODEL
PAPERLESS_AI_OLLAMA_URL=$PAPERLESS_AI_OLLAMA_URL
PAPERLESS_AI_OLLAMA_MODEL=$PAPERLESS_AI_OLLAMA_MODEL
PAPERLESS_AI_SCAN_INTERVAL=$PAPERLESS_AI_SCAN_INTERVAL
PAPERLESS_AI_ADD_TAG=$PAPERLESS_AI_ADD_TAG
PAPERLESS_AI_TAG_NAME=$PAPERLESS_AI_TAG_NAME
PAPERLESS_AI_PROCESS_PREDEFINED=$PAPERLESS_AI_PROCESS_PREDEFINED
ENVEOF

# Add paperless-ai to COMPOSE_PROFILES
CURRENT_PROFILES="${COMPOSE_PROFILES:-}"
if [ -z "$CURRENT_PROFILES" ]; then
    NEW_PROFILES="paperless-ai"
else
    # Remove any existing paperless-ai entry, then append
    STRIPPED=$(echo "$CURRENT_PROFILES" | sed 's/,\?paperless-ai,\?//g; s/^,//; s/,$//; s/,,/,/')
    NEW_PROFILES="${STRIPPED},paperless-ai"
fi
sed -i "s|^COMPOSE_PROFILES=.*|COMPOSE_PROFILES=$NEW_PROFILES|" "$INSTALL_DIR/.env"
success "COMPOSE_PROFILES updated: $NEW_PROFILES"

# Restart stack with new profile
info "Pulling paperless-ai image..."
cd "$INSTALL_DIR"
docker compose pull paperless-ai 2>/dev/null || warn "Could not pull image — will use cached version"

info "Starting paperless-ai..."
docker compose --env-file "$INSTALL_DIR/.env" up -d paperless-ai

# Wait a few seconds and check health
sleep 5
if docker compose ps paperless-ai 2>/dev/null | grep -q "Up"; then
    success "paperless-ai is running"
else
    warn "paperless-ai may still be starting up — check with: docker compose logs paperless-ai"
fi

# ── Summary ───────────────────────────────────────────────────
echo ""
echo -e "${GREEN}${BOLD}════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}${BOLD}  paperless-ai successfully installed!${NC}"
echo -e "${GREEN}${BOLD}════════════════════════════════════════════════════${NC}"
echo ""
echo -e "  ${BOLD}Web UI:${NC}          http://localhost:3000"
echo -e "  ${BOLD}AI Provider:${NC}     $PAPERLESS_AI_PROVIDER"
echo -e "  ${BOLD}Scan interval:${NC}   every ${PAPERLESS_AI_SCAN_INTERVAL} minutes"
if [ "$PAPERLESS_AI_ADD_TAG" = "true" ]; then
    echo -e "  ${BOLD}Tag:${NC}             $PAPERLESS_AI_TAG_NAME"
fi
echo ""

if [ -z "${PAPERLESS_API_TOKEN:-}" ]; then
    echo -e "${YELLOW}${BOLD}  Next step:${NC}"
    echo -e "  1. Generate an API token in the Paperless web UI"
    echo -e "     (Settings → API Tokens)"
    echo -e "  2. Add it to $INSTALL_DIR/.env:"
    echo -e "     ${CYAN}PAPERLESS_API_TOKEN=your-token${NC}"
    echo -e "  3. Restart paperless-ai:"
    echo -e "     ${CYAN}cd $INSTALL_DIR && docker compose up -d paperless-ai${NC}"
    echo ""
fi

echo -e "${DIM}  Logs:   cd $INSTALL_DIR && docker compose logs -f paperless-ai${NC}"
echo -e "${DIM}  Stop:   cd $INSTALL_DIR && docker compose stop paperless-ai${NC}"
echo ""
