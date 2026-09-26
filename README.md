# Channel TWRP / Recovery Wi-Fi

Recovery Wi-Fi development for the Motorola Moto G7 Play (`channel`).

The current user-facing TWRP build is available from the `main` branch through:

**Build Channel TWRP 3.5.2**

That workflow builds the current DroidSpaces recovery with Wi-Fi and hotspot support.

Basic recovery Wi-Fi commands:

```sh
wifi scan
wifi connect "SSID" "PASSWORD"
wifi status
wifi down
wifi up
wifi logs
```

For normal use, build from the **Actions** tab on `main`.
