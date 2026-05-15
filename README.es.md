# install-eduroam

Instalador limpio para conectar a la red Wi-Fi **eduroam** en Linux con NetworkManager.
Funciona con **cualquier institución** registrada en la base de datos de eduroam CAT (la mayoría de universidades y centros de investigación del mundo).

🇬🇧 [Read it in English](README.md)

## Instalación en una línea

Copia y pega en un terminal:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/drorganvidez/install-eduroam/main/install-eduroam.sh)
```

Te pedirá:

1. Tu país (menú).
2. Tu institución (menú).
3. Tu contraseña de `sudo`.
4. Tu usuario de eduroam (normalmente `usuario@tudominio`) y la contraseña.

Después conecta:

```bash
nmcli connection up eduroam
```

…o selecciona **eduroam** en el menú de Wi-Fi de GNOME/KDE.

## Opciones

```bash
install-eduroam.sh                # menú completo: país → universidad
install-eduroam.sh --country ES   # saltarse el menú de país (código ISO 3166)
install-eduroam.sh --profile 595  # sin menús, instala un perfil CAT concreto
```

## Qué hace

- Consulta el perfil de tu institución en la [API oficial de eduroam CAT](https://cat.eduroam.org/).
- Extrae el certificado CA, el servidor RADIUS, el método EAP (TTLS o PEAP), la autenticación interna (PAP/MSCHAPv2…) y la identidad anónima.
- Guarda el CA en `/etc/eduroam/ca.pem`.
- Crea `/etc/NetworkManager/system-connections/eduroam.nmconnection` con:
  - Validación de servidor mediante `domain-suffix-match` (sin avisos ni casilla que marcar a mano).
  - Contraseña guardada (sin reprompts).
- Borra cualquier perfil `eduroam` previo para evitar duplicados y recarga NetworkManager.

## Requisitos

- Distribución Linux con **NetworkManager** (Ubuntu, Fedora, Debian, Arch con GNOME/KDE…).
- `nmcli`, `curl`, `python3`, `uuidgen` (todos preinstalados en cualquier escritorio moderno).

## Desinstalar

```bash
sudo nmcli connection delete eduroam
sudo rm -f /etc/NetworkManager/system-connections/eduroam.nmconnection
sudo rm -rf /etc/eduroam
```

## Limitaciones

- EAP-TLS (autenticación con certificado personal) no está soportado. La mayoría de universidades usan TTLS/PAP o PEAP/MSCHAPv2, que sí funcionan.
- Tu institución tiene que estar registrada en CAT. Si no está, pídele a tu departamento de informática que suba el perfil — es gratis.
