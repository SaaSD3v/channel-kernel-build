# Recovery Wi-Fi + Hotspot — Moto G7 Play

Recovery networking for Motorola Moto G7 Play (`channel`) on the CLI-minimal branch.

## Wi-Fi client

```sh
wifi prepare
wifi up
wifi start
wifi scan
wifi connect "SSID" "PASSWORD"
wifi connect-sae "SSID" "PASSWORD"
wifi connect-open "SSID"
wifi status
wifi ping HOST
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
wifi networks
wifi forget "SSID"
wifi forget-all
wifi up
```

`wifi up` rebuilds the runtime supplicant configuration from saved `wlan/` profiles and attempts reassociation. Client DHCP has a lease watchdog so a BusyBox `udhcpc` process cannot keep the interactive recovery shell blocked after the lease has already been installed.

## Hotspot / ap0

Create or update the persistent AP profile:

```sh
wifi hotspot create "Channel-Recovery" "recovery123" 6
wifi hotspot config
wifi hotspot config ssid "Channel-New"
wifi hotspot config password "newpass123"
wifi hotspot config channel 149
wifi hotspot delete
```

AP-only mode still exists and uses `wlan0`:

```sh
wifi hotspot start
```

Concurrent AP/STA without NAT uses `ap0`:

```sh
wifi hotspot probe-vif
wifi hotspot start-vif "Channel-VIF" "recovery123"
wifi hotspot start-vif
```

Internet repeater mode uses `ap0 -> wlan0`, IPv4 forwarding and private legacy-iptables chains:

```sh
wifi hotspot repeater "Channel-Repeater" "recovery123"
wifi hotspot repeater-2g "Channel-2G" "recovery123"
wifi hotspot repeater-5g "Channel-5G" "recovery123"
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

It does not flush global DroidSpaces firewall state. `wifi hotspot stop` removes only those private chains and restores the prior `ip_forward` value.

## Diagnostics

```sh
wifi hotspot status
wifi hotspot clients
wifi status
wifi logs
wifi test
ds-recovery-check
```

`wifi ping HOST` falls back to BusyBox `nslookup` + IPv4 ping when the static libc resolver cannot resolve a hostname directly.

The CLI-minimal kernel deliberately keeps PRONTO/WCNSS, ADB, KGSL/Adreno, VIDC, namespaces/cgroups and DroidSpaces networking while physical framebuffer, touchscreen and camera paths are removed.
