# Recovery Wi-Fi — Moto G7 Play

Recovery Wi-Fi commands for the Motorola Moto G7 Play (`channel`).

## Connect

```sh
wifi scan
wifi connect "SSID" "PASSWORD"
wifi connect-sae "SSID" "PASSWORD"
wifi connect-open "SSID"
wifi status
```

## Saved networks

Successful connections can be stored under `/data/local/wifi/` when `/data` is available.

```sh
wifi networks
wifi forget "SSID"
wifi forget-all
wifi up
```

`wifi up` can reconnect to saved networks automatically.

## Other commands

```sh
wifi dhcp
wifi ping 1.1.1.1
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

The validated target is the Moto G7 Play (`channel`) using the PRONTO/WCNSS Wi-Fi path.
