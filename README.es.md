# linuxroam

Instalador limpio para conectar a la red Wi-Fi **eduroam** en Linux con NetworkManager.
Funciona con **cualquier institución** registrada en la base de datos de eduroam CAT (la mayoría de universidades y centros de investigación del mundo).

🇬🇧 [Read it in English](README.md)

## Instalación en una línea

Copia y pega en un terminal:

```bash
curl -fsSL https://install.linuxroam.com | bash
```

Hará:

1. **Detectar tu país automáticamente** (puedes cambiarlo).
2. Dejarte **buscar tu institución** por nombre.
3. Pedirte la contraseña de `sudo`.
4. Pedirte tu usuario de eduroam (normalmente `usuario@tudominio`) y la contraseña.

…y después **conecta solo**. Verás un progreso estilo docker mientras descarga
el perfil, instala el certificado y levanta la conexión.

> ¿Prefieres no canalizar a `bash`? Usa la forma equivalente con sustitución de proceso:
> ```bash
> bash <(curl -fsSL https://install.linuxroam.com)
> ```

## Opciones

```bash
curl -fsSL https://install.linuxroam.com | bash                       # flujo completo
curl -fsSL https://install.linuxroam.com | bash -s -- --country ES    # saltarse el menú de país (código CAT)
curl -fsSL https://install.linuxroam.com | bash -s -- --profile 595   # instala un perfil CAT concreto
```

## Qué hace

- Consulta el perfil de tu institución en la [API oficial de eduroam CAT](https://cat.eduroam.org/).
- Extrae el certificado CA, el servidor RADIUS, el método EAP (TTLS o PEAP), la autenticación interna (PAP/MSCHAPv2…) y la identidad anónima.
- Guarda el CA en `/etc/eduroam/ca.pem`.
- Crea `/etc/NetworkManager/system-connections/eduroam.nmconnection` con:
  - Validación de servidor mediante `domain-suffix-match` (sin avisos ni casilla que marcar a mano).
  - Contraseña guardada (sin reprompts).
- Borra cualquier perfil `eduroam` previo para evitar duplicados y recarga NetworkManager.

## Compatibilidad

El único requisito imprescindible es **NetworkManager**: el instalador
escribe un perfil `.nmconnection` y usa `nmcli`. Es independiente de la
arquitectura (no compila nada; solo bash + python + curl).

**✅ Funciona en cualquier distro que use NetworkManager**, que es lo
normal en escritorio:

- Ubuntu, Linux Mint, Pop!_OS, elementary…
- Fedora, openSUSE
- Debian (GNOME/KDE)
- Arch, Manjaro, EndeavourOS…

**❌ *No* funciona donde no hay NetworkManager:**

- Ubuntu Server / imágenes cloud (netplan + systemd-networkd)
- Configuraciones con `systemd-networkd` puro, `connman`, `wicd` o `wpa_supplicant` a pelo
- Sistemas mínimos/headless (p. ej. Alpine por defecto)

El script lo comprueba al principio y sale con un mensaje claro en lugar
de romperse a medias.

### Requisitos

- **NetworkManager** (`nmcli`).
- `bash`, `curl`, `python3`, `uuidgen` (`uuid-runtime` / `util-linux`), `sudo`.

Todos preinstalados en cualquier escritorio moderno; en sistemas mínimos
puede que tengas que instalar `bash` o `uuidgen`. Se recomienda un
NetworkManager reciente (de los últimos años): campos como
`domain-suffix-match` y `addr-gen-mode=default` necesitan NM ≥ 1.2 y
≥ 1.40 respectivamente.

## Desinstalar

```bash
sudo nmcli connection delete eduroam
sudo rm -f /etc/NetworkManager/system-connections/eduroam.nmconnection
sudo rm -rf /etc/eduroam
```

## Limitaciones

- EAP-TLS (autenticación con certificado personal) no está soportado. La mayoría de universidades usan TTLS/PAP o PEAP/MSCHAPv2, que sí funcionan.
- Tu institución tiene que estar registrada en CAT. Si no está, pídele a tu departamento de informática que suba el perfil — es gratis.

## Licencia

[Licencia Pública General de GNU v3.0](LICENSE) © David Romero.
