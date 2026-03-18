#!/usr/bin/env bash
# ╔══════════════════════════════════════════════════════════════╗
# ║  Paperless Overconfigured — Logrotate Setup                  ║
# ║                                                              ║
# ║  Konfiguriert logrotate für Paperless-Logs und richtet       ║
# ║  einen monatlichen Cronjob (1. des Monats) ein.              ║
# ║                                                              ║
# ║  Verwendung:                                                 ║
# ║    sudo bash scripts/setup-logrotate.sh [INSTALL_DIR]        ║
# ║                                                              ║
# ║  Beispiel:                                                   ║
# ║    sudo bash scripts/setup-logrotate.sh /opt/paperless       ║
# ║    sudo bash scripts/setup-logrotate.sh   # liest aus .env   ║
# ╚══════════════════════════════════════════════════════════════╝

set -euo pipefail

# ── Farben (nur im interaktiven Modus) ───────────────────────────────────────
if [ -t 1 ]; then
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    BLUE='\033[0;34m'
    CYAN='\033[0;36m'
    BOLD='\033[1m'
    NC='\033[0m'
else
    RED=''; GREEN=''; YELLOW=''; BLUE=''; CYAN=''; BOLD=''; NC=''
fi

info()    { echo -e "${BLUE}[INFO]${NC}  $*"; }
success() { echo -e "${GREEN}[OK]${NC}    $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC}  $*"; }
error()   { echo -e "${RED}[ERROR]${NC} $*" >&2; exit 1; }
step()    { echo -e "\n${CYAN}${BOLD}▶ $*${NC}"; }

# ── Root-Prüfung ─────────────────────────────────────────────────────────────
if [ "$EUID" -ne 0 ]; then
    error "Dieses Skript muss als root ausgeführt werden (sudo bash $0)"
fi

# ── Skript-Verzeichnis ermitteln ──────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# ── Install-Verzeichnis bestimmen ─────────────────────────────────────────────
# Priorität: 1) Argument, 2) .env-Datei, 3) Fehler
if [ -n "${1:-}" ]; then
    INSTALL_DIR="$1"
    info "Install-Verzeichnis (Argument): $INSTALL_DIR"
else
    # Suche .env in üblichen Pfaden
    ENV_FILE=""
    for candidate in "$REPO_DIR/.env" "/opt/paperless/.env" "$HOME/paperless/.env"; do
        if [ -f "$candidate" ]; then
            ENV_FILE="$candidate"
            break
        fi
    done

    if [ -n "$ENV_FILE" ]; then
        INSTALL_DIR="$(grep -E '^INSTALL_DIR=' "$ENV_FILE" 2>/dev/null | cut -d= -f2- | tr -d '"' | tr -d "'" || true)"
        if [ -z "$INSTALL_DIR" ]; then
            # Fallback: Verzeichnis der .env-Datei selbst
            INSTALL_DIR="$(dirname "$ENV_FILE")"
        fi
        info "Install-Verzeichnis (aus $ENV_FILE): $INSTALL_DIR"
    else
        error "Kein Install-Verzeichnis gefunden. Bitte als Argument übergeben:\n  sudo bash $0 /pfad/zu/paperless"
    fi
fi

# Pfad normalisieren und existenz prüfen
INSTALL_DIR="$(realpath "$INSTALL_DIR" 2>/dev/null || echo "$INSTALL_DIR")"
if [ ! -d "$INSTALL_DIR" ]; then
    error "Verzeichnis nicht gefunden: $INSTALL_DIR"
fi

# ── logrotate-Verfügbarkeit prüfen ────────────────────────────────────────────
if ! command -v logrotate &>/dev/null; then
    error "logrotate ist nicht installiert. Installation:\n  apt install logrotate   (Debian/Ubuntu)\n  dnf install logrotate   (Fedora/RHEL)"
fi

LOGROTATE_VERSION="$(logrotate --version 2>&1 | head -1)"
info "Gefunden: $LOGROTATE_VERSION"

# ── Template prüfen ───────────────────────────────────────────────────────────
TEMPLATE="$REPO_DIR/templates/logrotate-paperless.conf"
if [ ! -f "$TEMPLATE" ]; then
    error "Template nicht gefunden: $TEMPLATE"
fi

# ── Logs-Verzeichnis anlegen ──────────────────────────────────────────────────
step "Erstelle Log-Verzeichnis..."
LOGS_DIR="$INSTALL_DIR/logs"
if [ ! -d "$LOGS_DIR" ]; then
    mkdir -p "$LOGS_DIR"
    success "Verzeichnis erstellt: $LOGS_DIR"
else
    success "Verzeichnis vorhanden: $LOGS_DIR"
fi

# ── logrotate-Konfiguration schreiben ─────────────────────────────────────────
step "Schreibe logrotate-Konfiguration..."
LOGROTATE_CONF="/etc/logrotate.d/paperless"

sed "s|__INSTALL_DIR__|$INSTALL_DIR|g" "$TEMPLATE" > "$LOGROTATE_CONF"
chmod 644 "$LOGROTATE_CONF"
success "Konfiguration geschrieben: $LOGROTATE_CONF"

# Konfiguration prüfen
if logrotate --debug "$LOGROTATE_CONF" &>/dev/null; then
    success "Konfiguration ist gültig"
else
    warn "logrotate --debug meldet Hinweise (meist unbedenklich bei fehlenden Log-Dateien)"
fi

# ── Monatlichen Cronjob einrichten (1. des Monats) ────────────────────────────
step "Richte monatlichen Cronjob ein (1. des Monats, 02:00 Uhr)..."

CRON_MARKER="logrotate-paperless-monthly"
CRON_LINE="0 2 1 * * /usr/sbin/logrotate $LOGROTATE_CONF >> $INSTALL_DIR/logs/logrotate.log 2>&1 # $CRON_MARKER"

# Prüfen ob Cronjob bereits existiert (root-crontab)
if crontab -u root -l 2>/dev/null | grep -qF "$CRON_MARKER"; then
    success "Cronjob bereits vorhanden — keine Änderung"
else
    (crontab -u root -l 2>/dev/null || true; echo "$CRON_LINE") | crontab -u root -
    success "Cronjob eingerichtet: monatlich am 1., 02:00 Uhr"
fi

# ── Abschluss ─────────────────────────────────────────────────────────────────
echo ""
echo -e "${CYAN}${BOLD}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}${BOLD}║  Setup abgeschlossen                                         ║${NC}"
echo -e "${CYAN}${BOLD}╚══════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "  ${BOLD}Install-Verzeichnis:${NC}  $INSTALL_DIR"
echo -e "  ${BOLD}logrotate-Config:${NC}     $LOGROTATE_CONF"
echo -e "  ${BOLD}Log-Archiv:${NC}           $LOGS_DIR"
echo -e "  ${BOLD}Cronjob:${NC}              monatlich am 1. des Monats, 02:00 Uhr"
echo ""
echo -e "  ${BOLD}Manueller Test:${NC}"
echo -e "  ${BLUE}  sudo logrotate --force $LOGROTATE_CONF${NC}"
echo ""
echo -e "  ${BOLD}Cronjob anzeigen:${NC}"
echo -e "  ${BLUE}  sudo crontab -u root -l | grep logrotate${NC}"
echo ""
