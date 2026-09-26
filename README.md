# Channel Kernel Build

Builds for the Motorola Moto G7 Play (`channel`).

## GitHub Actions

The repository exposes four manual builds:

- **Build Channel Kernel 17.1**
- **Build Channel Kernel 18.1**
- **Build Channel Kernel 22.2**
- **Build Channel TWRP 3.5.2**

For the LineageOS kernels, use the default **NORMAL** variant for the complete project build.

The TWRP workflow directly builds the current recovery with:

- DroidSpaces
- recovery Wi-Fi
- persistent known Wi-Fi networks
- recovery hotspot
- validated `wlan0` + `ap0` STA/AP support

Successful builds are available as GitHub Actions artifacts.

## Recovery Wi-Fi

The TWRP build provides the `wifi` command in recovery.

```sh
wifi scan
wifi connect "SSID" "PASSWORD"
wifi connect-sae "SSID" "PASSWORD"
wifi connect-open "SSID"
wifi status
wifi networks
wifi forget "SSID"
wifi down
wifi up
wifi logs
```

## Recovery hotspot

Create and start a saved WPA2 hotspot:

```sh
wifi hotspot create "Channel-Recovery" "recovery123"
wifi hotspot start
wifi hotspot status
wifi hotspot clients
```

Manage or remove it:

```sh
wifi hotspot config
wifi hotspot config ssid "Channel-New" channel 6
wifi hotspot stop
wifi hotspot delete
```

The recovery hotspot uses `192.168.43.1/24`. It is a local recovery network and does not provide Internet/NAT tethering.

## Device support

The currently validated target is the Motorola Moto G7 Play (`channel`, SDM632, PRONTO/WCNSS, arm64).
