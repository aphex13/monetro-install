#!/usr/bin/env bash
# Monetra — Self-Hosting Installer
# Usage: curl -fsSL https://raw.githubusercontent.com/aphex13/monetro-install/main/install.sh | bash -s -- --key=MON-XXXX-XXXX-XXXX
set -euo pipefail

API_BASE="https://app.monetro.at/api/install"
INSTALL_DIR="${MONETRA_DIR:-/opt/monetra}"
LICENSE_KEY=""

# ── Argumente parsen ──────────────────────────────────────────────────────────
for arg in "$@"; do
  case $arg in
    --key=*) LICENSE_KEY="${arg#*=}" ;;
    --dir=*) INSTALL_DIR="${arg#*=}" ;;
  esac
done

# Bei "curl | bash" ist stdin die Pipe (kein TTY).
# HAS_TTY steuert ob gum und interaktive Prompts möglich sind.
HAS_TTY=false
[ -t 0 ] && HAS_TTY=true

# ── Farben & Helpers (Fallback ohne Gum) ──────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'
plain_info()    { echo -e "${CYAN}  →${NC} $*"; }
plain_success() { echo -e "${GREEN}  ✓${NC} $*"; }
plain_error()   { echo -e "${RED}  ✗${NC} $*" >&2; exit 1; }

# ── Gum installieren (nur wenn echtes TTY vorhanden) ──────────────────────────
install_gum() {
  if command -v brew >/dev/null 2>&1; then
    brew install gum >/dev/null 2>&1
  elif command -v apt-get >/dev/null 2>&1; then
    mkdir -p /etc/apt/keyrings
    curl -fsSL https://repo.charm.sh/apt/gpg.key | gpg --dearmor -o /etc/apt/keyrings/charm.gpg 2>/dev/null
    echo "deb [signed-by=/etc/apt/keyrings/charm.gpg] https://repo.charm.sh/apt/ * *" \
      > /etc/apt/sources.list.d/charm.list
    apt-get update -qq && apt-get install -y -qq gum >/dev/null 2>&1
  else
    GUM_VERSION="0.14.5"
    OS=$(uname -s | tr '[:upper:]' '[:lower:]')
    ARCH=$(uname -m); [ "$ARCH" = "x86_64" ] && ARCH="amd64" || ARCH="arm64"
    curl -fsSL "https://github.com/charmbracelet/gum/releases/download/v${GUM_VERSION}/gum_${GUM_VERSION}_${OS}_${ARCH}.tar.gz" \
      | tar -xz -C /usr/local/bin gum 2>/dev/null || return 1
  fi
}

HAS_GUM=false
if $HAS_TTY; then
  if ! command -v gum >/dev/null 2>&1; then
    plain_info "Installiere gum (Terminal-UI)..."
    install_gum || true
  fi
  command -v gum >/dev/null 2>&1 && HAS_GUM=true
fi

# ── UI Helpers ────────────────────────────────────────────────────────────────
header() {
  echo ""
  echo -e "${CYAN}${BOLD}"
  echo "        ███╗   ███╗"
  echo "        ████╗ ████║"
  echo "        ██╔████╔██║"
  echo "        ██║╚██╔╝██║"
  echo "        ██║ ╚═╝ ██║"
  echo "        ╚═╝     ╚═╝"
  echo -e "${NC}"
  echo -e "        ${BOLD}Monetra${NC}  ${CYAN}·${NC}  Self-Hosting Installer"
  echo -e "        ${CYAN}──────────────────────────────${NC}"
  echo ""
}

info() {
  if $HAS_GUM; then gum style --foreground 12 "  → $*"
  else plain_info "$*"; fi
}

success() {
  if $HAS_GUM; then gum style --foreground 2 "  ✓ $*"
  else plain_success "$*"; fi
}

error() {
  if $HAS_GUM; then gum style --foreground 1 --bold "  ✗ $*" >&2
  else plain_error "$*" >&2; fi
  exit 1
}

spin() {
  local title="$1"; shift
  if $HAS_GUM; then gum spin --spinner dot --title "  $title" -- "$@"
  else plain_info "$title"; "$@"; fi
}

prompt_input() {
  local label="$1" placeholder="${2:-}" val
  if $HAS_GUM; then
    gum input --placeholder "$placeholder" --prompt "  ${label}: " \
      --prompt.foreground 6 --width 50
  elif [ -e /dev/tty ]; then
    printf "  %s: " "$label" > /dev/tty; read -r val < /dev/tty; echo "$val"
  else
    printf "  %s: " "$label"; read -r val; echo "$val"
  fi
}

prompt_password() {
  local label="$1" val
  if $HAS_GUM; then
    gum input --password --placeholder "••••••••" --prompt "  ${label}: " \
      --prompt.foreground 6 --width 50
  elif [ -e /dev/tty ]; then
    printf "  %s: " "$label" > /dev/tty; read -rs val < /dev/tty; echo "" > /dev/tty; echo "$val"
  else
    printf "  %s: " "$label"; read -rs val; echo ""; echo "$val"
  fi
}

# ── Header ────────────────────────────────────────────────────────────────────
header

# ── Lizenzkey prüfen ─────────────────────────────────────────────────────────
if [ -z "$LICENSE_KEY" ]; then
  if $HAS_GUM; then
    LICENSE_KEY=$(gum input \
      --placeholder "MON-XXXX-XXXX-XXXX" \
      --prompt "  Lizenzkey: " \
      --prompt.foreground 6 \
      --width 30)
  elif [ -e /dev/tty ]; then
    printf "  Lizenzkey: " > /dev/tty; read -r LICENSE_KEY < /dev/tty
  else
    printf "  Lizenzkey: "; read -r LICENSE_KEY
  fi
fi

[ -z "$LICENSE_KEY" ] && error "Kein Lizenzkey angegeben."

info "Validiere Lizenzkey..."
VALIDATE_RESP=$(curl -sSL "${API_BASE}/validate?key=${LICENSE_KEY}" 2>/dev/null || echo '{}')
VALID=$(echo "$VALIDATE_RESP" | grep -o '"valid":true' || true)

if [ -z "$VALID" ]; then
  ERR_MSG=$(echo "$VALIDATE_RESP" | grep -oE '"message":"[^"]*"' | cut -d'"' -f4 || echo "Ungültiger Lizenzkey")
  error "$ERR_MSG"
fi

GHCR_TOKEN=$(echo "$VALIDATE_RESP" | grep -oE '"ghcrToken":"[^"]*"' | cut -d'"' -f4)
PLAN=$(echo "$VALIDATE_RESP" | grep -oE '"plan":"[^"]*"' | cut -d'"' -f4)
success "Lizenzkey gültig · Plan: ${PLAN}"

# ── Voraussetzungen ───────────────────────────────────────────────────────────
command -v docker >/dev/null 2>&1 || error "Docker nicht gefunden: https://docs.docker.com/get-docker/"
docker compose version >/dev/null 2>&1 || error "Docker Compose (v2) nicht gefunden: https://docs.docker.com/compose/install/"
command -v openssl >/dev/null 2>&1 || command -v xxd >/dev/null 2>&1 || error "openssl oder xxd wird benötigt."

DOCKER_VER=$(docker --version | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)
success "Docker ${DOCKER_VER} gefunden"

# ── GHCR Login ───────────────────────────────────────────────────────────────
if [ -n "$GHCR_TOKEN" ]; then
  echo "$GHCR_TOKEN" | docker login ghcr.io -u monetra-bot --password-stdin >/dev/null 2>&1 \
    && success "GHCR angemeldet" \
    || info "GHCR-Login fehlgeschlagen — versuche trotzdem fortzufahren"
fi

# ── Installationsverzeichnis ──────────────────────────────────────────────────
info "Installationsverzeichnis: ${INSTALL_DIR}"
if [ ! -d "$INSTALL_DIR" ]; then
  sudo mkdir -p "$INSTALL_DIR"
  sudo chown "$(id -u):$(id -g)" "$INSTALL_DIR"
fi
cd "$INSTALL_DIR"

# ── docker-compose.yml herunterladen ─────────────────────────────────────────
spin "Lade docker-compose.yml..." \
  curl -fsSL "${API_BASE%/install}/install/compose" -o docker-compose.yml 2>/dev/null || \
  curl -fsSL "https://raw.githubusercontent.com/aphex13/monetro-install/main/docker-compose.selfhost.yml" -o docker-compose.yml
success "docker-compose.yml geladen"

# ── .env erstellen ────────────────────────────────────────────────────────────
if [ -f .env ]; then
  info ".env existiert bereits — wird nicht überschrieben"
else
  echo ""
  if $HAS_GUM; then
    gum style --foreground 6 --bold "  Admin-Zugangsdaten"
    gum style --foreground 8 "  Diese werden für den ersten Login benötigt."
    echo ""
  else
    echo -e "  ${BOLD}Admin-Zugangsdaten${NC} (für den ersten Login)"
    echo ""
  fi

  [ -z "${ADMIN_EMAIL:-}" ]    && ADMIN_EMAIL=$(prompt_input "Admin E-Mail" "admin@example.com")
  [ -z "${ADMIN_PASSWORD:-}" ] && ADMIN_PASSWORD=$(prompt_password "Admin Passwort")

  echo ""
  info "Erstelle .env mit zufälligen Sicherheitsschlüsseln..."

  if command -v openssl >/dev/null 2>&1; then
    _rand() { openssl rand -hex "$1"; }
  else
    _rand() { xxd -l "$1" -p /dev/urandom | tr -d '\n'; }
  fi

  cat > .env <<EOF
# ── Datenbank ─────────────────────────────────────────────────────────────────
POSTGRES_DB=monetra
POSTGRES_USER=monetra
POSTGRES_PASSWORD=$(_rand 16)

# ── Sicherheitsschlüssel (NICHT ändern nach erstem Start!) ───────────────────
JWT_SECRET=$(_rand 32)
JWT_REFRESH_SECRET=$(_rand 32)
ENCRYPTION_KEY=$(_rand 32)

# ── Admin-Account ─────────────────────────────────────────────────────────────
ADMIN_EMAIL=${ADMIN_EMAIL}
ADMIN_PASSWORD=${ADMIN_PASSWORD}

# ── Lizenzkey ─────────────────────────────────────────────────────────────────
INSTALL_LICENSE_KEY=${LICENSE_KEY}

# ── App-URL ───────────────────────────────────────────────────────────────────
FRONTEND_URL=http://localhost
ALLOWED_ORIGINS=http://localhost
HTTP_PORT=80

# ── E-Mail / SMTP (optional) ──────────────────────────────────────────────────
SMTP_HOST=
SMTP_PORT=587
SMTP_USER=
SMTP_PASS=
SMTP_FROM=Monetra <noreply@example.com>

# ── KI-Assistent (optional) ───────────────────────────────────────────────────
ANTHROPIC_API_KEY=
AI_PROVIDER=anthropic

# ── Stripe Billing (optional) ─────────────────────────────────────────────────
STRIPE_SECRET_KEY=
STRIPE_WEBHOOK_SECRET=
EOF

  success ".env erstellt"
fi

# ── Images pullen & starten ───────────────────────────────────────────────────
echo ""
spin "Lade Docker-Images (kann einige Minuten dauern)..." \
  docker compose pull

spin "Starte Monetra..." \
  docker compose up -d

# ── Warten bis Backend bereit ist ────────────────────────────────────────────
info "Warte auf Backend..."
for i in $(seq 1 30); do
  if docker compose logs backend 2>&1 | grep -q "Server running\|listening on\|started"; then
    break
  fi
  sleep 2
done

# ── Fertig ────────────────────────────────────────────────────────────────────
PORT=$(grep "^HTTP_PORT=" .env 2>/dev/null | cut -d= -f2 || echo 80)
ADMIN_MAIL=$(grep '^ADMIN_EMAIL=' .env | cut -d= -f2)

echo ""
if $HAS_GUM; then
  gum style \
    --border rounded --border-foreground 2 \
    --padding "1 4" --margin "0 2" \
    "$(gum style --foreground 2 --bold "  Monetra läuft!")" \
    "" \
    "$(gum style --foreground 7 "  App:    http://localhost:${PORT}")" \
    "$(gum style --foreground 7 "  Login:  ${ADMIN_MAIL}")"
  echo ""
  gum style --foreground 8 --margin "0 4" \
    "Nächste Schritte:" \
    "  nano ${INSTALL_DIR}/.env   # SMTP, Domain, KI-Key konfigurieren" \
    "" \
    "Befehle:" \
    "  docker compose -C ${INSTALL_DIR} logs -f" \
    "  docker compose -C ${INSTALL_DIR} down" \
    "  docker compose -C ${INSTALL_DIR} pull && docker compose -C ${INSTALL_DIR} up -d"
else
  echo -e "  ${GREEN}${BOLD}Monetra läuft!${NC}"
  echo "  ─────────────────────────────────────────"
  echo -e "  App:    ${CYAN}http://localhost:${PORT}${NC}"
  echo -e "  Login:  ${ADMIN_MAIL}"
  echo ""
  echo "  Logs:   docker compose -C ${INSTALL_DIR} logs -f"
  echo "  Stop:   docker compose -C ${INSTALL_DIR} down"
  echo "  Update: docker compose -C ${INSTALL_DIR} pull && docker compose -C ${INSTALL_DIR} up -d"
fi
echo ""
