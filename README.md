# install-eduroam

Clean installer to join the **eduroam** Wi-Fi network on Linux with NetworkManager.
Works for **any institution** registered in the eduroam CAT database (most universities and research centers worldwide).

🇪🇸 [Léelo en español](README.es.md)

## One-line install

Paste in your terminal:

```bash
curl -fsSL https://install.linuxroam.com | bash
```

It will:

1. **Auto-detect your country** (you can change it).
2. Let you **search your institution** by name.
3. Ask for your `sudo` password.
4. Ask for your eduroam username (usually `user@yourdomain`) and password.

…then **connect automatically**. You'll see docker-style progress as it
downloads the profile, installs the certificate and brings the connection up.

> Prefer not to pipe into `bash`? Use the equivalent process-substitution form:
> ```bash
> bash <(curl -fsSL https://install.linuxroam.com)
> ```

## Options

```bash
curl -fsSL https://install.linuxroam.com | bash                       # full flow
curl -fsSL https://install.linuxroam.com | bash -s -- --country ES    # skip country menu (CAT code)
curl -fsSL https://install.linuxroam.com | bash -s -- --profile 595   # install a CAT profile by ID
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
