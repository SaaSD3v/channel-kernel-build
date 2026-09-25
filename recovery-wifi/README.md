# Recovery Wi-Fi — Motorola Moto G7 Play (channel)

This branch adds a self-contained Wi-Fi stack for the TeamWin TWRP 3.5.2_10-0 recovery on Motorola Moto G7 Play (channel / SDM632).

The `wifi ...` commands documented here are **custom commands provided by this project through `/sbin/wifi`**. They are not standard Android or TWRP commands.

## Quick start

Scan nearby networks:

```sh
wifi scan
```

Connect to a WPA/WPA2 network:

```sh
wifi connect "SSID" "PASSWORD"
```

Example:

```sh
wifi connect "Josiane" "your_password"
```

Connect to WPA3/SAE:

```sh
wifi connect-sae "SSID" "PASSWORD"
```

Connect to an open network:

```sh
wifi connect-open "SSID"
```

Check connection, IP address, routes and DNS:

```sh
wifi status
```

Test connectivity:

```sh
wifi ping 1.1.1.1
```

## Commands

| Command | Purpose |
|---|---|
| `wifi prepare` | Mount/stage required vendor, modem, persist and WCNSS firmware data, then initialize PRONTO/WCNSS and expose `wlan0`. |
| `wifi up` | Bring Wi-Fi userspace up. If a saved network profile exists in the current recovery session, reassociate and restore DHCP automatically. |
| `wifi scan` | Start Wi-Fi if necessary and list nearby access points. |
| `wifi connect "SSID" "PASSWORD"` | Connect to WPA/WPA2-PSK and obtain an IP address through DHCP. |
| `wifi connect-sae "SSID" "PASSWORD"` | Connect to WPA3-SAE and obtain an IP address through DHCP. |
| `wifi connect-open "SSID"` | Connect to an open network and obtain an IP address through DHCP. |
| `wifi dhcp` | Request/refresh IPv4 configuration through DHCP. |
| `wifi status` | Show supplicant state, interface addresses, routes and DNS. |
| `wifi ping HOST` | Ping a host through the recovery Wi-Fi connection. |
| `wifi disconnect` | Disconnect the current Wi-Fi network and clear interface addressing without shutting down the driver. |
| `wifi down` | Stop the recovery Wi-Fi userspace and bring `wlan0` down. |
| `wifi logs` | Print recovery Wi-Fi, wpa_supplicant and WCNSS/PRONTO diagnostics. |

## Recovery Wi-Fi stack

The command frontend is:

```text
/sbin/wifi
```

It drives the self-contained recovery binaries:

```text
/sbin/busybox.ds
/sbin/wpa_supplicant.ds
/sbin/wpa_cli.ds
/sbin/wpa_passphrase.ds
/sbin/wifi-udhcpc.script
/sbin/wcnss-recovery
```

The recovery Wi-Fi payload is embedded in the kernel internal initramfs. The external TeamWin recovery ramdisk remains byte-for-byte unchanged by the build workflow.

Temporary Wi-Fi state is kept under:

```text
/tmp/ds-wifi
```

The controller forces `TMPDIR=/tmp` so it does not depend on encrypted or unavailable `/data/local` storage in recovery.

## Driver bring-up

For channel, the recovery path stages the stock Motorola WCNSS/PRONTO firmware and calibration inputs before triggering the WLAN driver. The helper performs the WCNSS recovery handshake and the controller then requests PRONTO STA initialization through the kernel `fwpath` parameter.

Once `wlan0` exists, repeated `wifi prepare` calls preserve the already-running driver rather than retriggering the one-shot WCNSS control path.

## Verified hardware behavior

The current implementation has been tested on a physical Moto G7 Play in TWRP recovery with:

- WCNSS subsystem initialization
- PRONTO WLAN initialization
- `wlan0` creation
- repeated Wi-Fi scans
- WPA2-PSK association
- DHCP lease acquisition
- IPv4 default route
- DNS resolution
- IPv6 addressing
- Internet connectivity by IP and hostname
- `wifi down` followed by `wifi up`
- automatic reassociation and DHCP restoration after `wifi up`

A successful restart cycle should include:

```text
Wi-Fi ready on wlan0
Wi-Fi connection and DHCP restored on wlan0
```

followed by `wpa_state=COMPLETED`, an IP address and a default route in `wifi status`.

## Troubleshooting

If initialization, association or DHCP fails:

```sh
wifi logs
```

For a quick state check:

```sh
wifi status
```

For driver-only validation:

```sh
wifi prepare
ls -l /sys/class/net/wlan0
```

The `wifi scan` command only scans. It does not connect to an access point. Use one of the `wifi connect*` commands to create a network profile and establish connectivity.
