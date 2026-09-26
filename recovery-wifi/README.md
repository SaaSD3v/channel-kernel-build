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

Create one persistent WPA2 recovery hotspot profile (2.4 GHz, channel 6 by default):

```sh
wifi hotspot create "Channel-Recovery" "recovery123"
```

A second `create` is refused while a saved hotspot already exists. Change the
existing profile instead; multiple fields can be changed in one command:

```sh
wifi hotspot config
wifi hotspot config ssid "Channel-New"
wifi hotspot config password "newpass123"
wifi hotspot config channel 11
wifi hotspot config ssid "Channel-New" channel 6
```

`wifi hotspot config` never prints the saved password in clear text. The
profile is stored root-only in `/data/local/wifi/hotspot.conf`. Starting and
stopping are separate from profile management:

```sh
wifi hotspot start
wifi hotspot status
wifi hotspot clients
wifi hotspot stop
wifi hotspot delete
```

`stop` leaves the saved profile intact. `delete` removes the saved profile
without implicitly stopping an already-running hotspot; if one is active it
continues until `wifi hotspot stop`.

The recovery hotspot uses `192.168.43.1/24` and serves DHCP leases from
`192.168.43.20` through `192.168.43.60`. It is currently a local recovery
LAN, not an Internet/NAT tethering service. The separate experimental
`start-vif` path has been hardware-validated with `wlan0` STA and `ap0` AP
running concurrently on the PRONTO single-channel radio; the persistent
profile lifecycle remains independent from that experimental path.

## Commands

| Command | Purpose |
|---|---|
| `wifi prepare` | Mount/stage required vendor, modem, persist and WCNSS firmware data, then initialize PRONTO/WCNSS and expose `wlan0`. |
| `wifi up` | Bring Wi-Fi userspace up. If a saved network profile exists in the current recovery session, reassociate and restore DHCP automatically. |
| `wifi scan` | Start Wi-Fi if necessary and list nearby access points. |
| `wifi connect "SSID" "PASSWORD"` | Connect to WPA/WPA2-PSK and obtain an IP address through DHCP. |
| `wifi connect-sae "SSID" "PASSWORD"` | Connect to WPA3-SAE and obtain an IP address through DHCP. |
| `wifi connect-open "SSID"` | Connect to an open network and obtain an IP address through DHCP. |
| `wifi hotspot create "SSID" "PASSWORD" [CHANNEL]` | Create the single saved WPA2-PSK hotspot profile. Refuses to overwrite an existing profile. Channel defaults to 6; valid values are 1-11. |
| `wifi hotspot config` | Show the saved hotspot profile with the password hidden. |
| `wifi hotspot config KEY VALUE [KEY VALUE ...]` | Update `ssid`, `password`/`pass`, and/or `channel` in the saved profile. |
| `wifi hotspot start` | Start the hotspot using the saved AP configuration. |
| `wifi hotspot stop` | Stop AP/DHCP runtime and keep the saved profile. |
| `wifi hotspot delete` | Delete the saved hotspot profile without implicitly stopping an active runtime. |
| `wifi hotspot status` | Show AP state, interface address and DHCP-server status. |
| `wifi hotspot clients` | Show the AP neighbor/client table. |
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
/sbin/hostapd.ds
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

For channel, the recovery path stages the stock Motorola WCNSS/PRONTO firmware and calibration inputs before triggering the WLAN driver. The helper performs the WCNSS recovery handshake and the controller writes the built-in driver's `fwpath` parameter once to trigger PRONTO initialization. In this kernel the value itself is not a STA/AP selector; changing `fwpath` after initialization would restart the WLAN driver.

Once `wlan0` exists, repeated `wifi prepare` calls preserve the already-running driver rather than retriggering the one-shot WCNSS control path. Hotspot mode therefore uses a dedicated `hostapd` process on the driver's advertised cfg80211/nl80211 AP path to switch `wlan0` dynamically instead of restarting PRONTO through `fwpath` or `con_mode`.

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


## Persistent known networks

Validated networks are stored root-only under:

```text
/data/local/wifi/
├── .version
└── networks/
    └── <sha256-of-SSID>.conf
```

The persistent directory and network database use mode `0700`; individual
profiles use mode `0600` and root ownership. Runtime sockets, logs, PID files,
the active aggregate and connection candidates remain under `/tmp/ds-wifi`.

A network is persisted only after wpa_supplicant reaches
`wpa_state=COMPLETED` and DHCP succeeds. A wrong password, SAE failure,
association timeout or DHCP failure therefore cannot replace a previously
working saved profile.

```sh
wifi connect "SSID" "PASSWORD"
wifi connect-sae "SSID" "PASSWORD"
wifi connect-open "SSID"
wifi networks
wifi forget "SSID"
wifi forget-all
wifi up
```

`wifi up` rebuilds the runtime wpa_supplicant configuration from every saved
network, so multiple known networks survive recovery reboots and can
auto-associate without re-entering their password. If `/data` is unavailable,
a successful connection remains usable for the current recovery session but is
not persisted.


## Hotspot validation state

The hotspot implementation is kept separate from the already validated client
Wi-Fi path. CI validates the shell controller, builds a dedicated static `hostapd` over
`nl80211`, includes BusyBox `udhcpd`, stages the same compact internal
initramfs payload, and rebuilds the TWRP image. The already validated client
path continues to use its separate `wpa_supplicant` process.

Physical-device validation still needs to confirm beacon visibility, WPA2
association, DHCP lease delivery, client reachability to `192.168.43.1`, and
the AP-to-STA restore path. Until that test is completed, the client Wi-Fi
results listed above remain the hardware-validated baseline.
