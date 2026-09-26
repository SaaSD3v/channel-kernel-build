# Channel TWRP / Wi-Fi + Hotspot

Current recovery networking implementation for the Motorola Moto G7 Play (`channel`).

The user-facing build is available from the `main` branch through:

**Build Channel TWRP 3.5.2**

It builds the current DroidSpaces recovery with:

- recovery Wi-Fi
- persistent known networks
- persistent WPA2 hotspot profile
- `wlan0` station support
- validated `ap0` hotspot support

Common Wi-Fi commands:

```sh
wifi scan
wifi connect "SSID" "PASSWORD"
wifi status
wifi networks
wifi down
wifi up
wifi logs
```

Common hotspot commands:

```sh
wifi hotspot create "Channel-Recovery" "recovery123"
wifi hotspot start
wifi hotspot status
wifi hotspot clients
wifi hotspot stop
wifi hotspot delete
```

See [recovery-wifi/README.md](recovery-wifi/README.md) for the complete command reference.
