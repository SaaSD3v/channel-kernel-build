# Channel TWRP CLI Minimal

Headless/CLI recovery work for Motorola Moto G7 Play (`channel`), based on the known-good Channel TWRP 3.5.2 + DroidSpaces + recovery Wi-Fi/hotspot tree.

Stable source branch:

```text
twrp-3.5.2_10-0-droidspaces-wifi-hotspot
```

Development branch:

```text
twrp-cli-minimal
```

The stable branch is not modified by this work.

## Stage-1 minimal kernel

Removed from the physical handset path:

- framebuffer / MDSS display stack
- display-bias/backlight drivers tied to the physical panel
- touchscreen and desktop-pointer classes
- camera / camera-flash stack

Preserved deliberately:

- ADB / USB gadget / FunctionFS
- input core, EVDEV, UINPUT and hardware buttons
- PRONTO/WCNSS Wi-Fi
- KGSL/Adreno + IOMMU
- VIDC
- firmware loader
- DroidSpaces namespaces, cgroups, veth/bridge, OverlayFS and legacy netfilter/NAT

Audio, Bluetooth/NFC, haptics and nonessential USB functions are intentionally deferred until real-device boot + ADB validation.

## Recovery networking

The branch carries the full Channel Wi-Fi client plus the Albus-style runtime features adapted to Channel:

- validated persistent `wlan/` profiles
- persistent `ap0/` profile
- AP-only mode
- `ap0` STA+AP concurrency
- automatic repeater
- explicit 2.4 GHz and 5 GHz repeater modes
- private iptables NAT chains
- DHCP watchdog
- bounded wpa_supplicant startup
- static-DNS resolver fallback
- recovery one-shot time repair
- `ds-recovery-check`

See [recovery-wifi/README.md](recovery-wifi/README.md).

## Validation policy

CI success proves compilation, image structure, static userspace and configuration contracts. It does **not** prove device boot.

Do not make second-round kernel cuts until the current stage boots on a real Channel device and ADB is confirmed.
