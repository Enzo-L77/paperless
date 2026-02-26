#!/usr/bin/env bash
# firewall-tailscale-ssh.sh
#
# Schränkt SSH-Zugriff auf das Tailscale-Netzwerk ein.
# Nach Ausführung ist Port 22 nur noch über die Tailscale-Verbindung
# (Interface tailscale0 / Subnetz 100.64.0.0/10) erreichbar.
#
# Voraussetzungen:
#   - UFW installiert und aktiv
#   - Tailscale installiert und verbunden (tailscale up)
#
# Verwendung:
#   sudo bash scripts/firewall-tailscale-ssh.sh

set -euo pipefail

# ── Farben ──────────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

info()    { echo -e "${GREEN}[INFO]${NC}  $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC}  $*"; }
error()   { echo -e "${RED}[ERROR]${NC} $*" >&2; exit 1; }

# ── Vorbedingungen prüfen ────────────────────────────────────────────────────
[ "$EUID" -eq 0 ] || error "Dieses Skript muss als root ausgeführt werden (sudo)."

command -v ufw      &>/dev/null || error "UFW ist nicht installiert."
command -v tailscale &>/dev/null || error "Tailscale ist nicht installiert."

# Tailscale-Verbindung prüfen
if ! tailscale status &>/dev/null; then
    error "Tailscale ist nicht verbunden. Bitte zuerst 'tailscale up' ausführen."
fi

# Tailscale-Interface ermitteln (Standard: tailscale0)
TS_IFACE=$(ip -o link show | awk -F': ' '{print $2}' | grep '^tailscale' | head -n1)
[ -n "$TS_IFACE" ] || error "Kein Tailscale-Interface gefunden (erwartet: tailscale0)."

info "Tailscale-Interface erkannt: ${TS_IFACE}"
info "Tailscale-Subnetz:           100.64.0.0/10"

# ── Sicherheitsabfrage ───────────────────────────────────────────────────────
warn "ACHTUNG: Nach dieser Änderung ist SSH nur noch über Tailscale erreichbar."
warn "Stelle sicher, dass du mit Tailscale verbunden bist, bevor du fortfährst."
echo
read -r -p "Fortfahren? [j/N] " CONFIRM
[[ "$CONFIRM" =~ ^[jJyY]$ ]] || { echo "Abgebrochen."; exit 0; }

# ── Bestehende SSH-Regeln entfernen ──────────────────────────────────────────
info "Entferne bestehende OpenSSH-Regeln..."
# Alle Varianten, die der Installer oder manuell gesetzt haben könnte
ufw delete allow OpenSSH    2>/dev/null || true
ufw delete allow 22/tcp     2>/dev/null || true
ufw delete allow 22         2>/dev/null || true
ufw delete allow ssh        2>/dev/null || true

# ── SSH nur über Tailscale erlauben ─────────────────────────────────────────
info "Erlaube SSH ausschließlich über ${TS_IFACE} (Tailscale)..."

# Primär: Interface-basierte Regel (WireGuard-verschlüsselt, nicht spoofbar)
ufw allow in on "${TS_IFACE}" to any port 22 proto tcp \
    comment 'SSH nur via Tailscale' >/dev/null

# Zusätzlich: Subnetz-basierte Absicherung für Tailscale-Subnet-Routes
ufw allow from 100.64.0.0/10 to any port 22 proto tcp \
    comment 'SSH via Tailscale-Subnetz 100.64.0.0/10' >/dev/null

# ── UFW neu laden ────────────────────────────────────────────────────────────
info "Lade UFW-Regeln neu..."
ufw --force enable  >/dev/null
ufw reload          >/dev/null

# ── Ergebnis anzeigen ────────────────────────────────────────────────────────
echo
info "Fertig. Aktuelle UFW-Regeln für Port 22:"
ufw status verbose | grep -E '(22|ssh|SSH|Tailscale)' || true
echo
info "SSH ist jetzt nur noch über Tailscale erreichbar."
info "Überprüfung: sudo ufw status verbose"
