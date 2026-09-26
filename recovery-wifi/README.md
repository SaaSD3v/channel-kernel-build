# Recovery Wi-Fi + Hotspot — Moto G7 Play

Recovery networking commands for the Motorola Moto G7 Play (`channel`).

## Wi-Fi

```sh
wifi scan
wifi connect "SSID" "PASSWORD"
wifi connect-sae "SSID" "PASSWORD"
wifi connect-open "SSID"
wifi status
wifi ping 1.1.1.1
```

## Saved networks

Successful connections are stored under `/data/local/wifi/` when `/data` is available.

```sh
wifi networks
wifi forget "SSID"
wifi forget-all
wifi up
```

`wifi up` can automatically reconnect to saved networks.

## Hotspot

Create one saved WPA2 hotspot profile:

```sh
wifi hotspot create "Channel-Recovery" "recovery123"
```

Change the saved profile:

```sh
wifi hotspot config
wifi hotspot config ssid "Channel-New"
wifi hotspot config password "newpass123"
wifi hotspot config channel 11
wifi hotspot config ssid "Channel-New" channel 6
```

Start and manage the hotspot:

```sh
wifi hotspot start
wifi hotspot status
wifi hotspot clients
wifi hotspot stop
wifi hotspot delete
```

The hotspot uses `192.168.43.1/24` with DHCP leases from `192.168.43.20` to `192.168.43.60`.

It is a local recovery LAN and does not provide Internet/NAT tethering.

The project also contains the validated `ap0` STA/AP concurrency path for running station Wi-Fi and an access point together on the Moto G7 Play.

## Other commands

```sh
wifi dhcp
wifi disconnect
wifi down
wifi up
wifi logs
```

## Troubleshooting

```sh
wifi status
wifi logs
wifi prepare
ls -l /sys/class/net/wlan0
```

The currently validated hardware target is the Moto G7 Play (`channel`, SDM632, PRONTO/WCNSS).
