# Channel Kernel Build

Automated kernel builds for Motorola Moto G7 Play (channel).

## Supported branches

- `lineage-17.1`
- `lineage-18.1`
- `lineage-22.2`

## Which variant should I use?

The same four variants are available for every supported branch.

| Variant | KernelSU / ReSukiSU | DroidSpaces / fixes | Optional flags | Recommended when... |
|---|---|---|---|---|
| **NORMAL** | ✅ Included | ✅ Included | ✅ Included | You want the complete build with KSU and all DroidSpaces features. |
| **OPTIONAL** | ✅ Included | ✅ Included | ❌ Removed | You want KSU + DroidSpaces/fixes, but **without the optional flags**. |
| **KSU-ONLY** | ✅ Included | ❌ Removed | ❌ Removed | You want a near-stock branch baseline with **only KernelSU/ReSukiSU** added. |
| **REMOVE-KSU** | ❌ Removed | ✅ Included | ✅ Included | You want the complete DroidSpaces build, including optional features, but **without KernelSU**. |

## Quick selection

- **Want everything + KSU:** `NORMAL`
- **Want KSU + DroidSpaces but no optional flags:** `OPTIONAL`
- **Want only KSU, without DroidSpaces extras:** `KSU-ONLY`
- **Want DroidSpaces complete but no KSU:** `REMOVE-KSU`

### Examples

- LineageOS 17.1 + KSU + no optional flags → **`17.1 OPTIONAL`**
- LineageOS 18.1 + DroidSpaces complete + no KSU → **`18.1 REMOVE-KSU`**
- LineageOS 22.2 + only KSU → **`22.2 KSU-ONLY`**
- LineageOS 22.2 + everything → **`22.2 NORMAL`**

## Downloads

Each successful workflow publishes the kernel ZIP as a GitHub Actions artifact and uploads it to GoFile when `GOFILE_TOKEN` is configured.

## Usage

Open the **Actions** tab, select the workflow matching your Android branch and desired variant, then choose **Run workflow**.

## TWRP / DroidSpaces recovery branches

The repository also carries the recovery work used for DroidSpaces and recovery Wi-Fi on the Motorola Moto G7 Play (`channel`):

| Branch | Purpose |
|---|---|
| `twrp-3.5.2_10-0-droidspaces` | TWRP 3.5.2_10-0 baseline with DroidSpaces kernel support. |
| `twrp-3.5.2_10-0-droidspaces-wifi` | Recovery Wi-Fi development branch. |
| `twrp-3.5.2_10-0-droidspaces-wifi-kernel-initramfs` | Self-contained recovery Wi-Fi payload embedded in the kernel internal initramfs. |
| `twrp-3.5.2_10-0-droidspaces-wifi-hotspot` | Current Wi-Fi + persistent hotspot + STA/AP concurrency development branch. |

The hotspot branch is the current reference for the recovery Wi-Fi userspace and porting work.

## Recovery Wi-Fi / hotspot portability

The recovery Wi-Fi stack is split conceptually into two layers:

- **Common userspace:** static `wpa_supplicant`, `hostapd`, `iw`, BusyBox DHCP/network tools and the `wifi` command frontend.
- **Device-specific integration:** recovery kernel/config, firmware locations, WLAN driver bring-up, TWRP/boot-image packaging, DTB/DTBO handling and AP/virtual-interface support.

The currently validated hardware is **Motorola Moto G7 Play (`channel`, SDM632, PRONTO/WCNSS, arm64)**. Do not assume its WCNSS firmware staging or `/dev/wcnss_*` initialization works on another device unchanged.

The current hotspot branch supports a per-device userspace build profile:

```text
recovery-wifi/devices/
├── README.md
└── channel/
    └── device.conf
```

The default remains `channel`:

```sh
recovery-wifi/build-userspace.sh
```

or explicitly:

```sh
DEVICE=channel recovery-wifi/build-userspace.sh
```

For another device, add `recovery-wifi/devices/<codename>/device.conf` with its architecture/toolchain settings, then adapt the device-specific kernel, recovery image packaging, firmware staging and WLAN bring-up. A userspace profile alone does not make an untested device supported.

For hotspot support, the target WLAN driver must expose AP operation through cfg80211/nl80211. The optional simultaneous STA + AP path additionally requires virtual-interface/concurrency support.

