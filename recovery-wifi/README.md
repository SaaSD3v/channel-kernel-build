# RCTools Networking — Moto G7 Play

Recovery networking for Motorola Moto G7 Play (`channel`) on the CLI-minimal branch. `rctools` is the single user-facing recovery CLI; networking is implemented by an internal backend.

## Wi-Fi client

```sh
rctools wifi prepare
rctools wifi up
rctools wifi start
rctools wifi scan
rctools wifi connect "SSID" "PASSWORD"
rctools wifi connect-sae "SSID" "PASSWORD"
rctools wifi connect-open "SSID"
rctools wifi status
rctools wifi ping HOST
```

Successful connections are validated before being persisted. Runtime state stays in `/tmp/ds-wifi`; persistent state is separated by interface:

```text
/data/local/wifi/
├── .version
├── wlan/
│   └── networks/
│       └── <sha256-ssid>.conf
└── ap0/
    └── hotspot.conf
```

The old Channel layout (`/data/local/wifi/networks` and `/data/local/wifi/hotspot.conf`) is migrated automatically when possible.

```sh
rctools wifi networks
rctools wifi forget "SSID"
rctools wifi forget-all
rctools wifi up
```

`rctools wifi up` rebuilds the runtime supplicant configuration from saved `wlan/` profiles and attempts reassociation. Client DHCP has a lease watchdog so a BusyBox `udhcpc` process cannot keep the interactive recovery shell blocked after the lease has already been installed.

## Hotspot / ap0

Create or update the persistent AP profile:

```sh
rctools hotspot create "Channel-Recovery" "recovery123" 6
rctools hotspot config
rctools hotspot config ssid "Channel-New"
rctools hotspot config password "newpass123"
rctools hotspot config channel 149
rctools hotspot delete
```

AP-only mode still exists and uses `wlan0`:

```sh
rctools hotspot start
```

Concurrent AP/STA without NAT uses `ap0`:

```sh
rctools hotspot probe-vif
rctools hotspot start-vif "Channel-VIF" "recovery123"
rctools hotspot start-vif
```

Internet repeater mode uses `ap0 -> wlan0`, IPv4 forwarding and private legacy-iptables chains:

```sh
rctools hotspot repeater "Channel-Repeater" "recovery123"
rctools hotspot repeater-2g "Channel-2G" "recovery123"
rctools hotspot repeater-5g "Channel-5G" "recovery123"
```

`repeater` follows the current upstream band automatically. `repeater-2g` and `repeater-5g` enforce the requested band and explain when `wlan0` is connected to the opposite band.

PRONTO STA+AP is treated as single-channel: `ap0` follows the current `wlan0` channel. 2.4 GHz uses `hw_mode=g`; supported 5 GHz channels use `hw_mode=a`.

The hotspot network is:

```text
gateway: 192.168.43.1/24
leases : 192.168.43.20 - 192.168.43.60
DNS    : first IPv4 nameserver from recovery, fallback 8.8.8.8
```

Repeater NAT uses only:

```text
CHANNEL_HOTSPOT_FWD
CHANNEL_HOTSPOT_NAT
```

It does not flush global DroidSpaces firewall state. `rctools hotspot stop` removes only those private chains and restores the prior `ip_forward` value.

## Diagnostics

```sh
rctools hotspot status
rctools hotspot clients
rctools wifi status
rctools wifi logs
rctools wifi test
rctools droidspaces check
```

`rctools wifi ping HOST` falls back to BusyBox `nslookup` + IPv4 ping when the static libc resolver cannot resolve a hostname directly.

The CLI-minimal kernel deliberately keeps PRONTO/WCNSS, ADB, KGSL/Adreno, VIDC, namespaces/cgroups and DroidSpaces networking while physical framebuffer, touchscreen and camera paths are removed.
