# Recovery Wi-Fi device profiles

Device profiles provide the userspace build settings used by `recovery-wifi/build-userspace.sh`.

The validated profile is:

```text
recovery-wifi/devices/channel/device.conf
```

Build it with:

```sh
DEVICE=channel recovery-wifi/build-userspace.sh
```

If `DEVICE` is omitted, `channel` is used.

## Adding a device

Create:

```text
recovery-wifi/devices/<codename>/device.conf
```

Required build settings:

```sh
DEVICE_CODENAME=<codename>
DEVICE_NAME="<device name>"
DS_WIFI_ARCH=arm64
DS_WIFI_CROSS=aarch64-linux-gnu-
DS_WIFI_HOST=aarch64-linux-gnu
DS_WIFI_OPENSSL_TARGET=linux-aarch64
```

A new device must also provide compatible recovery kernel support, firmware/driver initialization, boot-image packaging and cfg80211/nl80211 AP support where hotspot mode is required.
