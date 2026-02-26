#!/usr/bin/env bash
# ╔══════════════════════════════════════════════════════════════╗
# ║  Paperless Overconfigured — Docker Auto-Update               ║
# ║                                                              ║
# ║  Prüft alle laufenden Docker-Services auf neue Images und    ║
# ║  aktualisiert sie automatisch. Täglich per Cronjob.          ║
# ║                                                              ║
# ║  Verwendung:                                                 ║
# ║    bash scripts/docker-update.sh                             ║
# ║                                                              ║
# ║  Cronjob (täglich 04:00 Uhr):                                ║
# ║    0 4 * * * /pfad/zu/scripts/docker-update.sh \             ║
# ║              >> /pfad/zu/docker-update.log 2>&1              ║
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
    DIM='\033[2m'
    NC='\033[0m'
else
    RED=''; GREEN=''; YELLOW=''; BLUE=''; CYAN=''; BOLD=''; DIM=''; NC=''
fi

info()    { echo -e "${BLUE}[INFO]${NC}  $*"; }
success() { echo -e "${GREEN}[OK]${NC}    $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC}  $*"; }
error()   { echo -e "${RED}[ERROR]${NC} $*" >&2; exit 1; }
step()    { echo -e "\n${CYAN}${BOLD}▶ $*${NC}"; }

# ── Installationsverzeichnis ermitteln ───────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_DIR=""

for dir in "$(dirname "$SCRIPT_DIR")" "$HOME/paperless" "/opt/paperless"; do
    if [ -f "$dir/docker-compose.yml" ] && [ -f "$dir/.env" ]; then
        INSTALL_DIR="$dir"
        break
    fi
done

if [ -z "$INSTALL_DIR" ]; then
    error "Paperless-Installation nicht gefunden.
Erwartet docker-compose.yml + .env in:
  - $(dirname "$SCRIPT_DIR")
  - $HOME/paperless
  - /opt/paperless"
fi

cd "$INSTALL_DIR"

# ── Banner ────────────────────────────────────────────────────────────────────
echo ""
echo -e "${CYAN}${BOLD}$(printf '═%.0s' {1..62})${NC}"
printf '%s Docker Auto-Update — %s %s\n' \
    "${CYAN}${BOLD}║${NC}" "$(date '+%Y-%m-%d %H:%M:%S')" "${CYAN}${BOLD}║${NC}"
echo -e "${CYAN}${BOLD}$(printf '═%.0s' {1..62})${NC}"
echo -e "  ${DIM}Verzeichnis: $INSTALL_DIR${NC}"
echo ""

# ── Voraussetzungen prüfen ────────────────────────────────────────────────────
command -v docker       &>/dev/null || error "Docker ist nicht installiert."
docker compose version  &>/dev/null || error "Docker Compose ist nicht verfügbar."

# ── Laufende Dienste ermitteln ────────────────────────────────────────────────
step "Laufende Dienste ermitteln..."

mapfile -t SERVICES < <(docker compose ps --services --filter "status=running" 2>/dev/null || true)

if [ "${#SERVICES[@]}" -eq 0 ]; then
    warn "Keine laufenden Dienste gefunden — Stack läuft möglicherweise nicht."
    exit 0
fi

info "Gefundene Dienste: ${SERVICES[*]}"

# ── Aktuelle Image-IDs erfassen (vor dem Pull) ────────────────────────────────
step "Aktuelle Image-IDs erfassen..."

declare -A PRE_IDS
declare -A SERVICE_IMAGES

for service in "${SERVICES[@]}"; do
    container=$(docker compose ps -q "$service" 2>/dev/null | head -1 || true)
    if [ -n "$container" ]; then
        current_id=$(docker inspect "$container" --format '{{.Image}}' 2>/dev/null || echo "")
        image_name=$(docker inspect "$container" --format '{{.Config.Image}}' 2>/dev/null || echo "")
        PRE_IDS["$service"]="${current_id}"
        SERVICE_IMAGES["$service"]="${image_name}"
        info "  %-20s %s  (%s)" "$service" "${current_id:7:12}" "$image_name"
    else
        warn "  $service: Kein laufender Container gefunden"
    fi
done

# ── Neue Images herunterladen ─────────────────────────────────────────────────
step "Neue Images von Registry herunterladen..."

docker compose pull 2>&1 | while IFS= read -r line; do
    echo -e "  ${DIM}$line${NC}"
done

# ── Geänderte Services ermitteln ──────────────────────────────────────────────
step "Image-IDs vergleichen (vor ↔ nach Pull)..."

UPDATED_SERVICES=()

for service in "${SERVICES[@]}"; do
    image_name="${SERVICE_IMAGES[$service]:-}"
    pre_id="${PRE_IDS[$service]:-}"

    if [ -z "$image_name" ]; then
        warn "  $service: Image-Name unbekannt, überspringe"
        continue
    fi

    # ID des neu verfügbaren Images (nach dem Pull)
    post_id=$(docker image inspect "$image_name" --format '{{.Id}}' 2>/dev/null || echo "")

    if [ -z "$post_id" ]; then
        warn "  $service: Image '$image_name' nach Pull nicht inspizierbar"
        continue
    fi

    if [ "$pre_id" = "$post_id" ]; then
        info "  ✓ %-20s bereits aktuell  (%s)" "$service" "${post_id:7:12}"
    else
        success "  ↑ %-20s Update!  (%s → %s)" \
            "$service" "${pre_id:7:12}" "${post_id:7:12}"
        UPDATED_SERVICES+=("$service")
    fi
done

# ── Aktualisierte Services neu starten ───────────────────────────────────────
echo ""

if [ "${#UPDATED_SERVICES[@]}" -eq 0 ]; then
    success "Alle Services sind bereits auf dem neuesten Stand."
    echo -e "  ${DIM}Kein Neustart notwendig.${NC}"
else
    step "Aktualisierte Services neu starten (${#UPDATED_SERVICES[@]})..."

    for service in "${UPDATED_SERVICES[@]}"; do
        info "Starte neu: $service"
        docker compose up -d "$service" 2>&1 | while IFS= read -r line; do
            echo -e "  ${DIM}$line${NC}"
        done
        success "$service erfolgreich aktualisiert"
    done
fi

# ── Veraltete Images bereinigen ───────────────────────────────────────────────
step "Nicht mehr verwendete Images bereinigen..."

prune_out=$(docker image prune -f 2>&1 || true)
reclaimed=$(echo "$prune_out" | grep -oE 'Total reclaimed space: [^$]+' || echo "")

if [ -n "$reclaimed" ] && [[ "$reclaimed" != *"0B"* ]]; then
    success "Speicher freigegeben — $reclaimed"
else
    info "Keine veralteten Images zum Bereinigen"
fi

# ── Zusammenfassung ───────────────────────────────────────────────────────────
echo ""
echo -e "${CYAN}${BOLD}$(printf '═%.0s' {1..62})${NC}"
if [ "${#UPDATED_SERVICES[@]}" -gt 0 ]; then
    echo -e "  ${GREEN}${BOLD}✓ Aktualisiert:${NC} ${UPDATED_SERVICES[*]}"
else
    echo -e "  ${GREEN}${BOLD}✓ Alles aktuell — keine Änderungen${NC}"
fi
echo -e "  ${DIM}Abgeschlossen: $(date '+%Y-%m-%d %H:%M:%S')${NC}"
echo -e "${CYAN}${BOLD}$(printf '═%.0s' {1..62})${NC}"
echo ""
