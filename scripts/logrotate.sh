#!/usr/bin/env bash
# ╔══════════════════════════════════════════════════════════════╗
# ║  Paperless Overconfigured — Manual Log Rotation             ║
# ║                                                              ║
# ║  Führt logrotate manuell mit der Paperless-Konfiguration     ║
# ║  aus. Nützlich zum Testen oder für eine erzwungene Rotation. ║
# ║                                                              ║
# ║  Verwendung:                                                 ║
# ║    sudo bash scripts/logrotate.sh           # normal         ║
# ║    sudo bash scripts/logrotate.sh --force   # erzwingen      ║
# ║    sudo bash scripts/logrotate.sh --debug   # Vorschau       ║
# ╚══════════════════════════════════════════════════════════════╝

set -euo pipefail

LOGROTATE_CONF="/etc/logrotate.d/paperless"

# ── Root-Check ────────────────────────────────────────────────────────────────
if [[ $EUID -ne 0 ]]; then
    echo "Fehler: Dieses Skript muss als root ausgeführt werden (sudo)." >&2
    exit 1
fi

# ── logrotate verfügbar? ──────────────────────────────────────────────────────
if ! command -v logrotate &>/dev/null; then
    echo "Fehler: logrotate ist nicht installiert." >&2
    exit 1
fi

# ── Konfiguration vorhanden? ──────────────────────────────────────────────────
if [[ ! -f "$LOGROTATE_CONF" ]]; then
    echo "Fehler: Konfiguration nicht gefunden: $LOGROTATE_CONF" >&2
    echo "       Bitte zuerst install.sh ausführen." >&2
    exit 1
fi

# ── Argumente verarbeiten ─────────────────────────────────────────────────────
EXTRA_ARGS=()
for arg in "$@"; do
    case "$arg" in
        --force) EXTRA_ARGS+=("--force") ;;
        --debug) EXTRA_ARGS+=("--debug") ;;
        *)
            echo "Unbekanntes Argument: $arg" >&2
            echo "Verwendung: $0 [--force] [--debug]" >&2
            exit 1
            ;;
    esac
done

# ── Rotation ausführen ────────────────────────────────────────────────────────
echo "Starte Log-Rotation: $LOGROTATE_CONF"
logrotate "${EXTRA_ARGS[@]}" "$LOGROTATE_CONF"
echo "Log-Rotation abgeschlossen."
