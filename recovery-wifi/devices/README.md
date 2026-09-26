# Recovery Wi-Fi device profiles

The recovery Wi-Fi userspace build is shared, while kernel/recovery integration and WLAN bring-up are device-specific.

`channel` remains the default and the only hardware-validated profile in this branch.

## Layout

```text
recovery-wifi/
├── build-userspace.sh
├── wifi
├── hostapd.config
├── wpa_supplicant.config
└── devices/
    ├── README.md
    └── channel/
        └── device.conf
```

Build a profile with:

```sh
DEVICE=channel recovery-wifi/build-userspace.sh
```

If `DEVICE` is omitted, `channel` is used.

## Adding another device

Create `recovery-wifi/devices/<codename>/device.conf` and define at minimum:

```sh
DEVICE_CODENAME=<codename>
DEVICE_NAME="<device name>"
DS_WIFI_ARCH=arm64
DS_WIFI_CROSS=aarch64-linux-gnu-
DS_WIFI_HOST=aarch64-linux-gnu
DS_WIFI_OPENSSL_TARGET=linux-aarch64
```

The following metadata is recommended:

```sh
DS_WIFI_IFACE=wlan0
DS_WIFI_DRIVER=<driver family>
DS_WIFI_FIRMWARE=<firmware family>
DS_WIFI_KERNEL_IMAGE=<kernel image type>
DS_WIFI_BOOT_HEADER=<Android boot header version>
```

A userspace profile does **not** make the recovery port universal. A new device must also provide a working recovery kernel/config, matching firmware staging, WLAN driver initialization, TWRP/boot-image packaging, and AP support through cfg80211/nl80211.

For PRONTO/WCNSS devices, `recovery-wifi/wifi` can be used as the reference implementation. Other WLAN families should replace the device-specific firmware/driver bring-up while keeping the common `wpa_supplicant`, `hostapd`, `iw`, BusyBox DHCP, and command frontend where compatible.
