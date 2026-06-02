# linuxroam

Clean installer to join the **eduroam** Wi-Fi network on Linux with NetworkManager.
Works for **any institution** registered in the eduroam CAT database (most universities and research centers worldwide).

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

## Compatibility

The only hard requirement is **NetworkManager** — the installer writes an
`.nmconnection` profile and drives `nmcli`. It's architecture-independent
(no compiled code, just bash + python + curl).

**✅ Works on any distro that uses NetworkManager**, which is the norm on
the desktop:

- Ubuntu, Linux Mint, Pop!_OS, elementary…
- Fedora, openSUSE
- Debian (GNOME/KDE)
- Arch, Manjaro, EndeavourOS…

**❌ Does *not* work where there is no NetworkManager:**

- Ubuntu Server / cloud images (netplan + systemd-networkd)
- Plain `systemd-networkd`, `connman`, `wicd`, or raw `wpa_supplicant` setups
- Minimal/headless systems (e.g. Alpine by default)

The script checks this up front and exits with a clear message instead of
half-failing.

### Requirements

- **NetworkManager** (`nmcli`).
- `bash`, `curl`, `python3`, `uuidgen` (`uuid-runtime` / `util-linux`), `sudo`.

All preinstalled on any modern desktop distro; on minimal systems you may
need to install `bash` or `uuidgen`. A recent NetworkManager (last few
years) is recommended — fields like `domain-suffix-match` and
`addr-gen-mode=default` need NM ≥ 1.2 / ≥ 1.40 respectively.

## Uninstall

```bash
curl -fsSL https://install.linuxroam.com | bash -s -- --uninstall
```

This removes the `eduroam` connection, its NetworkManager profile and the
installed certificates. (Equivalent manual steps: `sudo nmcli connection
delete eduroam`, then remove `/etc/NetworkManager/system-connections/eduroam.nmconnection`
and `/etc/eduroam`.)

## Caveats

- EAP-TLS (personal-certificate-based) is not supported. Most universities use TTLS/PAP or PEAP/MSCHAPv2, which work.
- Your institution must be registered in CAT. If it's missing, ask your IT department to publish a profile there — it's free.

## License

[GNU General Public License v3.0](LICENSE) © David Romero.
