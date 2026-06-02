#!/usr/bin/env bash
# LINUXROAM — eduroam installer for Linux + NetworkManager.
# Pulls the institution profile from the eduroam CAT API and writes a clean
# /etc/NetworkManager/system-connections/eduroam.nmconnection
#
# Open source (MIT) · https://github.com/drorganvidez/install-eduroam
# Promoted by Diverso Lab · https://www.diversolab.us.es
#
# Usage:
#   curl -fsSL https://install.linuxroam.com | bash
#   curl -fsSL https://install.linuxroam.com | bash -s -- --country ES
#   curl -fsSL https://install.linuxroam.com | bash -s -- --profile 595

set -euo pipefail

CAT_API="https://cat.eduroam.org/user/API.php"
CONN_NAME="eduroam"
CA_DIR="/etc/eduroam"
NM_FILE="/etc/NetworkManager/system-connections/${CONN_NAME}.nmconnection"

COUNTRY=""
PROFILE_ID=""

usage() {
  cat >&2 <<'USAGE'
LINUXROAM — eduroam installer for Linux + NetworkManager

Usage:
  curl -fsSL https://install.linuxroam.com | bash
  curl -fsSL https://install.linuxroam.com | bash -s -- --country ES
  curl -fsSL https://install.linuxroam.com | bash -s -- --profile 595

Options:
  --country XX   Skip the country menu (CAT federation code, e.g. ES, UK).
  --profile N    Skip everything and install CAT profile id N.
  -h, --help     Show this help.
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --country) COUNTRY="$2"; shift 2 ;;
    --profile) PROFILE_ID="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; usage; exit 1 ;;
  esac
done

# --- UI / colors ---------------------------------------------------
if [[ -t 2 ]]; then
  CYN=$'\033[36m'; GRN=$'\033[32m'; RED=$'\033[31m'
  DIM=$'\033[2m';  BLD=$'\033[1m';  RST=$'\033[0m'
else
  CYN=""; GRN=""; RED=""; DIM=""; BLD=""; RST=""
fi

# --- helpers -------------------------------------------------------
banner() {
  printf '\n%s%s' "$BLD" "$CYN" >&2
  cat >&2 <<'BANNER'
    __    _____   ____  ___  __ ____  ____  ___    __  ___
   / /   /  _/ | / / / / / |/ // __ \/ __ \/   |  /  |/  /
  / /    / //  |/ / / / /|   // /_/ / / / / /| | / /|_/ /
 / /____/ // /|  / /_/ //   |/ _, _/ /_/ / ___ |/ /  / /
/_____/___/_/ |_/\____//_/|_/_/ |_|\____/_/  |_/_/  /_/
BANNER
  printf '%s' "$RST" >&2
  printf '%s  eduroam on Linux — one command, no GUI clicking%s\n\n' "$DIM" "$RST" >&2
  printf '  %sOpen source%s%s · MIT%s\n' "$BLD" "$RST" "$DIM" "$RST" >&2
  printf '  %sRepo:%s        https://github.com/drorganvidez/install-eduroam\n' "$BLD" "$RST" >&2
  printf '  %sPromoted by:%s Diverso Lab — https://www.diversolab.us.es\n' "$BLD" "$RST" >&2
  printf '  %sData source:%s eduroam CAT (cat.eduroam.org)\n\n' "$BLD" "$RST" >&2
}

# Run a command with a docker-compose-style spinner that turns into a
# check mark. Stdout of the command goes to $1 (a file); progress goes
# to stderr. Returns the command's exit status.
#   spin <outfile> "<message>" <cmd> [args...]
spin() {
  local out="$1" msg="$2"; shift 2
  if [[ ! -t 2 ]]; then
    if "$@" >"$out" 2>/dev/null; then
      printf ' %s✔%s %s\n' "$GRN" "$RST" "$msg" >&2; return 0
    else
      printf ' %s✗%s %s\n' "$RED" "$RST" "$msg" >&2; return 1
    fi
  fi
  "$@" >"$out" 2>/dev/null &
  local pid=$! frames='⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏' i=0
  while kill -0 "$pid" 2>/dev/null; do
    printf '\r %s%s%s %s ' "$CYN" "${frames:i++%${#frames}:1}" "$RST" "$msg" >&2
    sleep 0.08
  done
  if wait "$pid"; then
    printf '\r %s✔%s %s   \n' "$GRN" "$RST" "$msg" >&2; return 0
  else
    printf '\r %s✗%s %s   \n' "$RED" "$RST" "$msg" >&2; return 1
  fi
}

# Instant status line (for fast, non-blocking steps).
ok_step() { printf ' %s✔%s %s\n' "$GRN" "$RST" "$1" >&2; }

api_get() { curl -fsSL --max-time 20 "${CAT_API}?$1"; }

# Best-effort guess of the user's country (ISO 3166-1 alpha-2) from their
# public IP. Prints a CAT federation code on success, nothing on failure.
detect_country() {
  local cc
  cc=$(curl -fsSL --max-time 5 "https://ipinfo.io/country" 2>/dev/null | tr -d '[:space:]')
  [[ -z "$cc" ]] && cc=$(curl -fsSL --max-time 5 "http://ip-api.com/line/?fields=countryCode" 2>/dev/null | tr -d '[:space:]')
  cc=${cc^^}
  # CAT federation codes mostly match ISO; map the known exceptions.
  case "$cc" in
    GB) cc="UK" ;;
  esac
  [[ "$cc" =~ ^[A-Z]{2}$ ]] && printf '%s' "$cc"
}

pick_country() {
  local detected="${1:-}" tmp json
  tmp=$(mktemp)
  spin "$tmp" "Fetching country list" api_get "action=listCountries&lang=en" \
    || { rm -f "$tmp"; echo "Error: could not reach eduroam CAT." >&2; exit 1; }
  json=$(cat "$tmp"); rm -f "$tmp"
  python3 - "$json" "$detected" <<'PY'
import json, sys
data = json.loads(sys.argv[1])
detected = (sys.argv[2] if len(sys.argv) > 2 else '').strip().upper()
items = sorted(data.get('data', []), key=lambda x: x['display'].lower())
if not items:
    print("No countries returned by CAT API.", file=sys.stderr); sys.exit(2)

det_idx = next((i for i, it in enumerate(items)
                if it['federation'].upper() == detected), None)

for i, it in enumerate(items, 1):
    mark = '  <- detected' if det_idx == i - 1 else ''
    print(f"{i:>4}) {it['display']}  ({it['federation']}){mark}", file=sys.stderr)

if det_idx is not None:
    d = items[det_idx]
    print(f"\nDetected location: {d['display']} ({d['federation']}).", file=sys.stderr)
    print("Press Enter to accept, or type a number to change it: ", file=sys.stderr, end='')
else:
    print("Pick your country: ", file=sys.stderr, end='')

try:
    with open('/dev/tty') as tty:
        raw = tty.readline()
except OSError:
    sys.exit(2)
if raw == '':            # real EOF
    sys.exit(2)
line = raw.strip()
if line == '' and det_idx is not None:
    print(items[det_idx]['federation']); sys.exit(0)
try:
    sel = int(line)
except ValueError:
    sys.exit(2)
if not 1 <= sel <= len(items):
    sys.exit(2)
print(items[sel-1]['federation'])
PY
}

pick_idp() {
  local tmp json
  tmp=$(mktemp)
  spin "$tmp" "Fetching institutions for $COUNTRY" \
    api_get "action=listIdentityProviders&federation=${COUNTRY}&lang=en" \
    || { rm -f "$tmp"; echo "Error: could not list institutions." >&2; exit 1; }
  json=$(cat "$tmp"); rm -f "$tmp"
  python3 - "$json" "$COUNTRY" <<'PY'
import json, sys
data = json.loads(sys.argv[1])
items = sorted(data.get('data', []), key=lambda x: x['display'].lower())
if not items:
    print(f"No institutions found for country '{sys.argv[2]}'.", file=sys.stderr); sys.exit(2)

try:
    tty = open('/dev/tty')
except OSError:
    sys.exit(2)

def show(lst):
    for i, it in enumerate(lst, 1):
        print(f"{i:>4}) {it['display']}", file=sys.stderr)

current = items
show(current)
print(f"\n{len(items)} institutions. Type part of a name to search, "
      "or a number to pick: ", file=sys.stderr, end='')

while True:
    raw = tty.readline()
    if raw == '':                       # real EOF
        sys.exit(2)
    line = raw.strip()
    if line == '':
        if len(current) == 1:
            print(current[0]['idp']); sys.exit(0)
        print("Type a number or a search term: ", file=sys.stderr, end=''); continue
    if line.isdigit():
        sel = int(line)
        if 1 <= sel <= len(current):
            print(current[sel - 1]['idp']); sys.exit(0)
        print("Out of range. Try again: ", file=sys.stderr, end=''); continue
    q = line.lower()
    filtered = [it for it in items if q in it['display'].lower()]
    if not filtered:
        print(f"No match for '{line}'. Try another search, or a number: ",
              file=sys.stderr, end=''); continue
    current = filtered
    show(current)
    if len(current) == 1:
        print("\n1 match. Press Enter to pick it, or search again: ",
              file=sys.stderr, end='')
    else:
        print(f"\n{len(current)} matches. Type a number to pick, "
              "or refine the search: ", file=sys.stderr, end='')
PY
}

pick_profile() {
  local idp="$1" tmp json
  tmp=$(mktemp)
  spin "$tmp" "Fetching profiles" api_get "action=listProfiles&idp=${idp}&lang=en" \
    || { rm -f "$tmp"; echo "Error: could not list profiles." >&2; exit 1; }
  json=$(cat "$tmp"); rm -f "$tmp"
  python3 - "$json" <<'PY'
import json, sys
data = json.loads(sys.argv[1])
items = data.get('data', [])
if not items:
    print("The selected institution has no profile in CAT.", file=sys.stderr); sys.exit(2)
if len(items) == 1:
    print(items[0]['profile']); sys.exit(0)
for i, it in enumerate(items, 1):
    name = it.get('display') or it.get('idp_name') or it['profile']
    print(f"{i:>4}) {name}", file=sys.stderr)
print("This institution has multiple profiles. Pick one: ", file=sys.stderr, end='')
try:
    with open('/dev/tty') as tty:
        sel = int(tty.readline())
except (ValueError, EOFError, OSError):
    sys.exit(2)
if not 1 <= sel <= len(items):
    sys.exit(2)
print(items[sel-1]['profile'])
PY
}

# --- banner & preflight --------------------------------------------
banner

missing=()
for c in nmcli python3 curl uuidgen; do
  command -v "$c" >/dev/null 2>&1 || missing+=("$c")
done
if (( ${#missing[@]} )); then
  printf ' %s✗%s Missing required tools: %s%s%s\n' "$RED" "$RST" "$BLD" "${missing[*]}" "$RST" >&2
  printf '   Install them and re-run (uuidgen lives in uuid-runtime / util-linux).\n' >&2
  exit 1
fi
ok_step "Requirements satisfied (nmcli, python3, curl, uuidgen)"

# --- choose country, institution & profile -------------------------
if [[ -z "$PROFILE_ID" ]]; then
  if [[ -z "$COUNTRY" ]]; then
    dtmp=$(mktemp)
    spin "$dtmp" "Detecting your location" detect_country || true
    DETECTED=$(cat "$dtmp"); rm -f "$dtmp"
    COUNTRY=$(pick_country "$DETECTED")
  fi
  IDP_ID=$(pick_idp)
  PROFILE_ID=$(pick_profile "$IDP_ID")
fi

# --- download & parse EAP config -----------------------------------
EAP_XML=$(mktemp --suffix=.eap-config)
trap 'rm -f "$EAP_XML"' EXIT

spin "$EAP_XML" "Downloading institution profile & certificates" \
  curl -fsSL --max-time 30 \
  "${CAT_API}?action=downloadInstaller&lang=en&profile=${PROFILE_ID}&device=eap-config&generatedfor=user&openroaming=0" \
  || { echo "Error: could not download the profile from eduroam CAT." >&2; exit 1; }

parsed=$(python3 - "$EAP_XML" <<'PY'
import sys, xml.etree.ElementTree as ET, shlex, re
tree = ET.parse(sys.argv[1]); root = tree.getroot()

def strip_ns(tag): return re.sub(r'^\{[^}]+\}', '', tag)
def find(node, name):
    for c in node.iter():
        if strip_ns(c.tag) == name: return c
    return None
def find_all(node, name):
    return [c for c in node.iter() if strip_ns(c.tag) == name]

idp = find(root, 'EAPIdentityProvider')
realm = (idp.get('ID') or '').strip()
display = ''
for d in find_all(idp, 'DisplayName'):
    if d.get('lang') == 'en' or not display:
        display = (d.text or '').strip()

am = find(idp, 'AuthenticationMethod')
# Outer EAP type is the first <Type> in document order under AuthenticationMethod
eap_type = int(find_all(am, 'Type')[0].text)

server_ids = [s.text.strip() for s in find_all(am, 'ServerID') if s.text]
ca_b64 = ''
for c in find_all(am, 'CA'):
    if c.text: ca_b64 = ''.join(c.text.split()); break

outer_id = ''
oi = find(am, 'OuterIdentity')
if oi is not None and oi.text: outer_id = oi.text.strip()

inner_type = ''
inner_method = ''
iam = find(am, 'InnerAuthenticationMethod')
if iam is not None:
    non_eap = None; eap_inner = None
    for c in iam:
        n = strip_ns(c.tag)
        if n == 'NonEAPAuthMethod': non_eap = c
        elif n == 'EAPMethod':     eap_inner = c
    if non_eap is not None:
        t = find(non_eap, 'Type')
        inner_type = (t.text or '').strip() if t is not None else ''
        inner_method = 'noneap'
    elif eap_inner is not None:
        t = find(eap_inner, 'Type')
        inner_type = (t.text or '').strip() if t is not None else ''
        inner_method = 'eap'

def out(k, v): print(f"{k}={shlex.quote(v)}")
out('EAP_TYPE', str(eap_type))
out('REALM', realm)
out('DISPLAY', display)
out('SERVER_IDS', ';'.join(server_ids))
out('CA_B64', ca_b64)
out('OUTER_ID', outer_id)
out('INNER_TYPE', inner_type)
out('INNER_METHOD', inner_method)
PY
)
eval "$parsed"
ok_step "Selected: $DISPLAY  (realm: $REALM)"

# --- translate EAP method to NM fields -----------------------------
case "$EAP_TYPE" in
  21) NM_EAP="ttls" ;;
  25) NM_EAP="peap" ;;
  *)  echo "EAP method not supported by this installer: $EAP_TYPE" >&2; exit 1 ;;
esac

if [[ "$INNER_METHOD" == "noneap" ]]; then
  # 1=PAP, 2=CHAP, 3=MSCHAP, 4=MSCHAPv2
  case "$INNER_TYPE" in
    1) NM_PHASE2="pap" ;;
    2) NM_PHASE2="chap" ;;
    3) NM_PHASE2="mschap" ;;
    4) NM_PHASE2="mschapv2" ;;
    *) NM_PHASE2="pap" ;;
  esac
else
  # 26 = EAP-MSCHAPv2 (typical for PEAP)
  NM_PHASE2="mschapv2"
fi

# Domain match: longest common suffix of all ServerIDs.
NM_DOMAIN=$(python3 - "$SERVER_IDS" <<'PY'
import sys
ids = [x for x in sys.argv[1].split(';') if x]
if not ids: print(''); raise SystemExit
parts = [list(reversed(x.split('.'))) for x in ids]
common = []
for chunk in zip(*parts):
    if len(set(chunk)) == 1: common.append(chunk[0])
    else: break
print('.'.join(reversed(common)))
PY
)

# --- prompt credentials --------------------------------------------
# Read from /dev/tty so this works under `curl ... | bash`, where stdin
# is the script stream rather than the keyboard.
printf '\n' >&2
read -rp "Username (usually user@$REALM): " USERNAME </dev/tty
[[ -z "$USERNAME" ]] && { echo "Error: empty username" >&2; exit 1; }
if [[ -n "$REALM" && "$USERNAME" != *"@${REALM}" ]]; then
  printf ' %s!%s your username does not end with %s@%s%s — continuing anyway.\n' \
    "$RED" "$RST" "$BLD" "$REALM" "$RST" >&2
fi
read -rsp "Password: " PASSWORD </dev/tty; echo >&2
[[ -z "$PASSWORD" ]] && { echo "Error: empty password" >&2; exit 1; }

# --- elevate if needed and write everything as root ----------------
[[ $EUID -ne 0 ]] && printf ' %s•%s Root privileges required — asking sudo...\n' "$CYN" "$RST" >&2
exec sudo -E \
    USERNAME="$USERNAME" PASSWORD="$PASSWORD" \
    CONN_NAME="$CONN_NAME" CA_DIR="$CA_DIR" NM_FILE="$NM_FILE" \
    EAP_NM="$NM_EAP" PHASE2_NM="$NM_PHASE2" DOMAIN_NM="$NM_DOMAIN" \
    OUTER_ID="$OUTER_ID" DISPLAY="$DISPLAY" CA_B64="$CA_B64" \
    bash -s <<'ROOT'
set -euo pipefail

# Colors + docker-style step helpers (stderr is still the terminal here).
if [[ -t 2 ]]; then
  CYN=$'\033[36m'; GRN=$'\033[32m'; RED=$'\033[31m'; BLD=$'\033[1m'; RST=$'\033[0m'
else
  CYN=""; GRN=""; RED=""; BLD=""; RST=""
fi
ok_step() { printf ' %s✔%s %s\n' "$GRN" "$RST" "$1" >&2; }
spin() {  # spin "<message>" <cmd...>
  local msg="$1"; shift
  if [[ ! -t 2 ]]; then
    if "$@" >/dev/null 2>&1; then printf ' %s✔%s %s\n' "$GRN" "$RST" "$msg" >&2; return 0
    else printf ' %s✗%s %s\n' "$RED" "$RST" "$msg" >&2; return 1; fi
  fi
  "$@" >/dev/null 2>&1 &
  local pid=$! frames='⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏' i=0
  while kill -0 "$pid" 2>/dev/null; do
    printf '\r %s%s%s %s ' "$CYN" "${frames:i++%${#frames}:1}" "$RST" "$msg" >&2
    sleep 0.08
  done
  if wait "$pid"; then printf '\r %s✔%s %s   \n' "$GRN" "$RST" "$msg" >&2; return 0
  else printf '\r %s✗%s %s   \n' "$RED" "$RST" "$msg" >&2; return 1; fi
}

install -d -m 0755 "$CA_DIR"
CA_FILE="$CA_DIR/ca.pem"
{
  echo "-----BEGIN CERTIFICATE-----"
  echo "$CA_B64" | fold -w 64
  echo "-----END CERTIFICATE-----"
} >"$CA_FILE"
chmod 0644 "$CA_FILE"
ok_step "Installed CA certificate at $CA_FILE"

nmcli connection delete "$CONN_NAME" >/dev/null 2>&1 || true

UUID=$(uuidgen)
umask 077
{
  echo "[connection]"
  echo "id=$CONN_NAME"
  echo "uuid=$UUID"
  echo "type=wifi"
  echo "autoconnect=true"
  echo
  echo "[wifi]"
  echo "mode=infrastructure"
  echo "ssid=$CONN_NAME"
  echo
  echo "[wifi-security]"
  echo "key-mgmt=wpa-eap"
  echo
  echo "[802-1x]"
  echo "eap=$EAP_NM"
  echo "identity=$USERNAME"
  [[ -n "$OUTER_ID" ]] && echo "anonymous-identity=$OUTER_ID"
  echo "ca-cert=$CA_FILE"
  [[ -n "$DOMAIN_NM" ]] && echo "domain-suffix-match=$DOMAIN_NM"
  echo "phase2-auth=$PHASE2_NM"
  echo "password=$PASSWORD"
  echo
  echo "[ipv4]"
  echo "method=auto"
  echo
  echo "[ipv6]"
  echo "method=auto"
  echo "addr-gen-mode=default"
} >"$NM_FILE"
chmod 0600 "$NM_FILE"
chown root:root "$NM_FILE"
ok_step "Wrote NetworkManager profile ($NM_FILE)"

spin "Reloading NetworkManager" nmcli connection reload

printf '\n %s✔ Done.%s eduroam configured for %s%s%s (%s).\n\n' \
  "$GRN$BLD" "$RST" "$BLD" "$USERNAME" "$RST" "$DISPLAY" >&2

if spin "Connecting to $CONN_NAME" nmcli connection up "$CONN_NAME"; then
  printf ' %s✔%s You are now connected to %s%s%s.\n' "$GRN" "$RST" "$BLD" "$CONN_NAME" "$RST" >&2
else
  printf ' %s•%s Not connected yet (out of range?). It will join automatically\n' "$CYN" "$RST" >&2
  printf '   when in range, or run:  %snmcli connection up %s%s\n' "$BLD" "$CONN_NAME" "$RST" >&2
fi
ROOT
