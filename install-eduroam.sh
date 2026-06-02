#!/usr/bin/env bash
# Generic eduroam installer for Linux + NetworkManager.
# Pulls institution profile from the eduroam CAT API and writes a clean
# /etc/NetworkManager/system-connections/eduroam.nmconnection
#
# Usage:
#   ./install-eduroam.sh                # full menu: country -> institution
#   ./install-eduroam.sh --country ES   # skip country menu, jump to institutions
#   ./install-eduroam.sh --profile 595  # skip everything, install a CAT profile by ID

set -euo pipefail

CAT_API="https://cat.eduroam.org/user/API.php"
CONN_NAME="eduroam"
CA_DIR="/etc/eduroam"
NM_FILE="/etc/NetworkManager/system-connections/${CONN_NAME}.nmconnection"

COUNTRY=""
PROFILE_ID=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --country) COUNTRY="$2"; shift 2 ;;
    --profile) PROFILE_ID="$2"; shift 2 ;;
    -h|--help) sed -n '2,11p' "$0"; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; exit 1 ;;
  esac
done

# --- preflight -----------------------------------------------------
command -v nmcli   >/dev/null || { echo "Error: nmcli (NetworkManager) is not installed."   >&2; exit 1; }
command -v python3 >/dev/null || { echo "Error: python3 is not installed."                  >&2; exit 1; }
command -v curl    >/dev/null || { echo "Error: curl is not installed."                     >&2; exit 1; }
command -v uuidgen >/dev/null || { echo "Error: uuidgen is not installed (install uuid-runtime / util-linux)." >&2; exit 1; }

# --- helpers -------------------------------------------------------
api_get() { curl -fsSL --max-time 20 "${CAT_API}?$1"; }

pick_country() {
  local json
  echo "Fetching list of countries..." >&2
  json=$(api_get "action=listCountries&lang=en")
  python3 - "$json" <<'PY'
import json, sys
data = json.loads(sys.argv[1])
items = sorted(data.get('data', []), key=lambda x: x['display'].lower())
if not items:
    print("No countries returned by CAT API.", file=sys.stderr); sys.exit(2)
for i, it in enumerate(items, 1):
    print(f"{i:>4}) {it['display']}  ({it['federation']})", file=sys.stderr)
print("Pick your country: ", file=sys.stderr, end='')
try:
    with open('/dev/tty') as tty:
        sel = int(tty.readline())
except (ValueError, EOFError, OSError):
    sys.exit(2)
if not 1 <= sel <= len(items):
    sys.exit(2)
print(items[sel-1]['federation'])
PY
}

pick_idp() {
  local json
  echo "Fetching institutions for country '$COUNTRY'..." >&2
  json=$(api_get "action=listIdentityProviders&federation=${COUNTRY}&lang=en")
  python3 - "$json" "$COUNTRY" <<'PY'
import json, sys
data = json.loads(sys.argv[1])
items = sorted(data.get('data', []), key=lambda x: x['display'].lower())
if not items:
    print(f"No institutions found for country '{sys.argv[2]}'.", file=sys.stderr); sys.exit(2)
for i, it in enumerate(items, 1):
    print(f"{i:>4}) {it['display']}", file=sys.stderr)
print("Pick your institution: ", file=sys.stderr, end='')
try:
    with open('/dev/tty') as tty:
        sel = int(tty.readline())
except (ValueError, EOFError, OSError):
    sys.exit(2)
if not 1 <= sel <= len(items):
    sys.exit(2)
print(items[sel-1]['idp'])
PY
}

pick_profile() {
  local idp="$1" json
  json=$(api_get "action=listProfiles&idp=${idp}&lang=en")
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

# --- choose country, institution & profile -------------------------
if [[ -z "$PROFILE_ID" ]]; then
  if [[ -z "$COUNTRY" ]]; then
    COUNTRY=$(pick_country)
  fi
  IDP_ID=$(pick_idp)
  PROFILE_ID=$(pick_profile "$IDP_ID")
fi

# --- download & parse EAP config -----------------------------------
EAP_XML=$(mktemp --suffix=.eap-config)
trap 'rm -f "$EAP_XML"' EXIT

curl -fsSL --max-time 30 \
  "${CAT_API}?action=downloadInstaller&lang=en&profile=${PROFILE_ID}&device=eap-config&generatedfor=user&openroaming=0" \
  -o "$EAP_XML"

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

echo "Selected institution: $DISPLAY  (realm: $REALM)"

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
read -rp "Username (usually user@$REALM): " USERNAME
[[ -z "$USERNAME" ]] && { echo "Error: empty username" >&2; exit 1; }
if [[ -n "$REALM" && "$USERNAME" != *"@${REALM}" ]]; then
  echo "Warning: your username does not end with '@$REALM'. Continuing anyway."
fi
read -rsp "Password: " PASSWORD; echo
[[ -z "$PASSWORD" ]] && { echo "Error: empty password" >&2; exit 1; }

# --- elevate if needed and write everything as root ----------------
[[ $EUID -ne 0 ]] && echo "Root privileges required. Re-running with sudo..."
exec sudo -E \
    USERNAME="$USERNAME" PASSWORD="$PASSWORD" \
    CONN_NAME="$CONN_NAME" CA_DIR="$CA_DIR" NM_FILE="$NM_FILE" \
    EAP_NM="$NM_EAP" PHASE2_NM="$NM_PHASE2" DOMAIN_NM="$NM_DOMAIN" \
    OUTER_ID="$OUTER_ID" DISPLAY="$DISPLAY" CA_B64="$CA_B64" \
    bash -s <<'ROOT'
set -euo pipefail
install -d -m 0755 "$CA_DIR"
CA_FILE="$CA_DIR/ca.pem"
{
  echo "-----BEGIN CERTIFICATE-----"
  echo "$CA_B64" | fold -w 64
  echo "-----END CERTIFICATE-----"
} >"$CA_FILE"
chmod 0644 "$CA_FILE"

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

nmcli connection reload

echo
echo "Done. Connection '$CONN_NAME' created for $USERNAME ($DISPLAY)."
echo "To connect now:  nmcli connection up $CONN_NAME"
ROOT
