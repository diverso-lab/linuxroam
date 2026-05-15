# install-eduroam

Clean installer to join the **eduroam** Wi-Fi network on Linux with NetworkManager.
Works for **any institution** registered in the eduroam CAT database (most universities and research centers worldwide).

🇪🇸 [Léelo en español](README.es.md)

## One-line install

Paste in your terminal:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/drorganvidez/install-eduroam/main/install-eduroam.sh)
```

You will be prompted for:

1. Your country (menu).
2. Your institution (menu).
3. Your `sudo` password.
4. Your eduroam username (usually `user@yourdomain`) and password.

Then connect:

```bash
nmcli connection up eduroam
```

…or pick **eduroam** in the GNOME/KDE Wi-Fi menu.

## Options

```bash
install-eduroam.sh                # full menu: country -> institution
install-eduroam.sh --country ES   # skip country menu (ISO 3166 code)
install-eduroam.sh --profile 595  # skip everything, install a CAT profile by ID
```

## What it does

- Fetches your institution's profile from the official [eduroam CAT API](https://cat.eduroam.org/).
- Extracts the CA certificate, RADIUS server name, EAP method (TTLS or PEAP), inner auth (PAP/MSCHAPv2…) and anonymous identity.
- Writes the CA to `/etc/eduroam/ca.pem`.
- Creates `/etc/NetworkManager/system-connections/eduroam.nmconnection` with:
  - Server validation via `domain-suffix-match` (no warnings, no checkbox to tick).
  - Password stored (no reprompts).
- Removes any previous `eduroam` profile to avoid duplicates and reloads NetworkManager.

## Requirements

- Linux distribution with **NetworkManager** (Ubuntu, Fedora, Debian, Arch with GNOME/KDE…).
- `nmcli`, `curl`, `python3`, `uuidgen` (all preinstalled on any modern desktop distro).

## Uninstall

```bash
sudo nmcli connection delete eduroam
sudo rm -f /etc/NetworkManager/system-connections/eduroam.nmconnection
sudo rm -rf /etc/eduroam
```

## Caveats

- EAP-TLS (personal-certificate-based) is not supported. Most universities use TTLS/PAP or PEAP/MSCHAPv2, which work.
- Your institution must be registered in CAT. If it's missing, ask your IT department to publish a profile there — it's free.
