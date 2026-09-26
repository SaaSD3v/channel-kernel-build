# Channel TWRP / Recovery Wi-Fi

Recovery Wi-Fi work for the Motorola Moto G7 Play (`channel`).

The current user-facing build is available from the `main` branch through:

**Build Channel TWRP 3.5.2**

That workflow builds the current DroidSpaces recovery with Wi-Fi and hotspot support.

Common commands:

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

See [recovery-wifi/README.md](recovery-wifi/README.md) for recovery network usage.
