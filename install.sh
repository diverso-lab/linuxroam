#!/usr/bin/env bash
# LINUXROAM — eduroam installer for Linux + NetworkManager.
# Pulls the institution profile from the eduroam CAT API and writes a clean
# /etc/NetworkManager/system-connections/eduroam.nmconnection
#
# Copyright (C) 2026 David Romero
# Repo: https://github.com/diverso-lab/linuxroam
# Promoted by Diverso Lab · https://www.diversolab.us.es
#
# This program is free software: you can redistribute it and/or modify it
# under the terms of the GNU General Public License as published by the
# Free Software Foundation, either version 3 of the License, or (at your
# option) any later version. This program is distributed WITHOUT ANY
# WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
# FOR A PARTICULAR PURPOSE. See the GNU GPL v3 (LICENSE file) for details.
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
  printf '  %sOpen source%s%s · GNU GPLv3%s\n' "$BLD" "$RST" "$DIM" "$RST" >&2
  printf '  %sRepo:%s        https://github.com/diverso-lab/linuxroam\n' "$BLD" "$RST" >&2
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
    printf '\r\033[K %s%s%s %s' "$CYN" "${frames:i++%${#frames}:1}" "$RST" "$msg" >&2
    sleep 0.08
  done
  if wait "$pid"; then
    printf '\r\033[K %s✔%s %s\n' "$GRN" "$RST" "$msg" >&2; return 0
  else
    printf '\r\033[K %s✗%s %s\n' "$RED" "$RST" "$msg" >&2; return 1
  fi
}

# Instant status line (for fast, non-blocking steps).
ok_step() { printf ' %s✔%s %s\n' "$GRN" "$RST" "$1" >&2; }

# Short legal notice the user must acknowledge before anything runs.
disclaimer() {
  printf ' %s%sBefore you continue%s\n\n' "$BLD" "$CYN" "$RST" >&2
  printf '   %s•%s This installs an %seduroam%s Wi-Fi profile and stores your\n' "$CYN" "$RST" "$BLD" "$RST" >&2
  printf '     password locally in NetworkManager (a root-only file).\n' >&2
  printf '   %s•%s Your institution profile is fetched from the official\n' "$CYN" "$RST" >&2
  printf '     %seduroam CAT%s (cat.eduroam.org). Use only your own credentials\n' "$BLD" "$RST" >&2
  printf '     and follow your institution'"'"'s acceptable-use policy.\n' >&2
  printf '   %s•%s Provided %sas is%s, without warranty, under the %sGNU GPLv3%s.\n' "$CYN" "$RST" "$BLD" "$RST" "$BLD" "$RST" >&2
  printf '     Not affiliated with or endorsed by eduroam, GÉANT or your\n' >&2
  printf '     institution.\n\n' >&2
  printf '   %sPress [Enter] to accept and continue, or Ctrl+C to cancel.%s ' "$DIM" "$RST" >&2
  read -r _ </dev/tty || { printf '\n' >&2; exit 130; }
  printf '\n' >&2
}

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

tty_out = sys.stderr.isatty()
def c(code): return code if tty_out else ''
BLD, CYN, GRN, DIM, RST = (c('\033[1m'), c('\033[36m'), c('\033[32m'),
                           c('\033[2m'), c('\033[0m'))

det_idx = next((i for i, it in enumerate(items)
                if it['federation'].upper() == detected), None)

for i, it in enumerate(items, 1):
    mark = f'  {GRN}← detected{RST}' if det_idx == i - 1 else ''
    print(f"{i:>4}) {it['display']}  ({it['federation']}){mark}", file=sys.stderr)

if det_idx is not None:
    d = items[det_idx]
    print(f"\n {GRN}✔{RST} We think you're in "
          f"{BLD}{d['display']} ({d['federation']}){RST}.", file=sys.stderr)
    print(f"   {BLD}Press [Enter] to use it{RST}, "
          f"{DIM}or type another number from the list:{RST}", file=sys.stderr)
    print("   > ", file=sys.stderr, end='')
else:
    print(f"\n {BLD}Type the number of your country:{RST} ", file=sys.stderr, end='')

try:
    with open('/dev/tty') as tty:
        raw = tty.readline()
except OSError:
    sys.exit(2)
print('', file=sys.stderr)   # leave the prompt line cleanly
if raw == '':                # real EOF
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

tty_out = sys.stderr.isatty()
def c(code): return code if tty_out else ''
BLD, DIM, RST = c('\033[1m'), c('\033[2m'), c('\033[0m')

def show(lst):
    for i, it in enumerate(lst, 1):
        print(f"{i:>4}) {it['display']}", file=sys.stderr)

def chosen(idp):
    print('', file=sys.stderr)   # leave the prompt line cleanly
    print(idp); sys.exit(0)

current = items
show(current)
print(f"\n {BLD}{len(items)} institutions.{RST} "
      f"{DIM}Type part of the name to search, or its number to pick:{RST}",
      file=sys.stderr)
print("   > ", file=sys.stderr, end='')

while True:
    raw = tty.readline()
    if raw == '':                       # real EOF
        sys.exit(2)
    line = raw.strip()
    if line == '':
        if len(current) == 1:
            chosen(current[0]['idp'])
        print("   > ", file=sys.stderr, end=''); continue
    if line.isdigit():
        sel = int(line)
        if 1 <= sel <= len(current):
            chosen(current[sel - 1]['idp'])
        print(f"   {DIM}out of range — try again:{RST} > ", file=sys.stderr, end=''); continue
    q = line.lower()
    filtered = [it for it in items if q in it['display'].lower()]
    if not filtered:
        print(f"   {DIM}no match for '{line}' — search again, or type a number:{RST} > ",
              file=sys.stderr, end=''); continue
    current = filtered
    print('', file=sys.stderr)
    show(current)
    if len(current) == 1:
        print(f"\n {BLD}1 match.{RST} {DIM}Press [Enter] to pick it, "
              f"or search again:{RST}", file=sys.stderr)
    else:
        print(f"\n {BLD}{len(current)} matches.{RST} {DIM}Type its number to pick, "
              f"or refine the search:{RST}", file=sys.stderr)
    print("   > ", file=sys.stderr, end='')
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
tty_out = sys.stderr.isatty()
BLD = '\033[1m' if tty_out else ''
RST = '\033[0m' if tty_out else ''
for i, it in enumerate(items, 1):
    name = it.get('display') or it.get('idp_name') or it['profile']
    print(f"{i:>4}) {name}", file=sys.stderr)
print(f"\n {BLD}This institution has several profiles. Type its number:{RST} ",
      file=sys.stderr, end='')
try:
    with open('/dev/tty') as tty:
        raw = tty.readline()
    print('', file=sys.stderr)   # leave the prompt line cleanly
    sel = int(raw)
except (ValueError, EOFError, OSError):
    sys.exit(2)
if not 1 <= sel <= len(items):
    sys.exit(2)
print(items[sel-1]['profile'])
PY
}

# --- banner, disclaimer & preflight --------------------------------
banner
disclaimer

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
try:
    tree = ET.parse(sys.argv[1]); root = tree.getroot()
except Exception:
    print("The downloaded profile is not a valid eap-config.", file=sys.stderr)
    sys.exit(2)

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
if am is None:
    print("This profile has no authentication method CAT can install.", file=sys.stderr)
    sys.exit(2)
# Outer EAP type is the first <Type> in document order under AuthenticationMethod
type_nodes = [t for t in find_all(am, 'Type') if t.text and t.text.strip().isdigit()]
if not type_nodes:
    print("Could not read the EAP method from the profile.", file=sys.stderr)
    sys.exit(2)
eap_type = int(type_nodes[0].text)

server_ids = [s.text.strip() for s in find_all(am, 'ServerID') if s.text]
# Collect every CA in the chain (root + intermediates), not just the first.
cas = [''.join(c.text.split()) for c in find_all(am, 'CA') if c.text]
if not cas:
    print("The profile ships no CA certificate; refusing to install without "
          "server validation.", file=sys.stderr)
    sys.exit(2)

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
out('CA_B64', ' '.join(cas))   # space-separated base64 blobs (no inner spaces)
out('OUTER_ID', outer_id)
out('INNER_TYPE', inner_type)
out('INNER_METHOD', inner_method)
PY
) || { echo "Error: could not read the institution profile (see message above)." >&2; exit 1; }
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
printf ' %sUsername%s — e.g. %suser@%s%s (a subdomain like %suser@…%s%s is also valid).\n' \
  "$BLD" "$RST" "$BLD" "$REALM" "$RST" "$DIM" "$REALM" "$RST" >&2
read -rp "   > " USERNAME </dev/tty
[[ -z "$USERNAME" ]] && { echo "Error: empty username" >&2; exit 1; }
# Accept user@REALM and any subdomain user@<sub>.REALM (e.g. alum.us.es).
userdomain="${USERNAME##*@}"
if [[ -n "$REALM" && "$USERNAME" == *"@"* \
      && "$userdomain" != "$REALM" && "$userdomain" != *".$REALM" ]]; then
  printf ' %s!%s your domain (%s%s%s) is not under %s%s%s — continuing anyway.\n' \
    "$RED" "$RST" "$BLD" "$userdomain" "$RST" "$BLD" "$REALM" "$RST" >&2
elif [[ "$USERNAME" != *"@"* ]]; then
  printf ' %s!%s no %s@domain%s in your username — continuing anyway.\n' \
    "$RED" "$RST" "$BLD" "$RST" >&2
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
    printf '\r\033[K %s%s%s %s' "$CYN" "${frames:i++%${#frames}:1}" "$RST" "$msg" >&2
    sleep 0.08
  done
  if wait "$pid"; then printf '\r\033[K %s✔%s %s\n' "$GRN" "$RST" "$msg" >&2; return 0
  else printf '\r\033[K %s✗%s %s\n' "$RED" "$RST" "$msg" >&2; return 1; fi
}

install -d -m 0755 "$CA_DIR"
CA_FILE="$CA_DIR/ca.pem"
: >"$CA_FILE"
for b in $CA_B64; do
  {
    echo "-----BEGIN CERTIFICATE-----"
    echo "$b" | fold -w 64
    echo "-----END CERTIFICATE-----"
  } >>"$CA_FILE"
done
chmod 0644 "$CA_FILE"
CA_N=$(grep -c "BEGIN CERTIFICATE" "$CA_FILE")
ok_step "Installed CA chain at $CA_FILE ($CA_N certificate(s))"

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
