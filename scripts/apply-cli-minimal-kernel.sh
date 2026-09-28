#!/usr/bin/env bash
set -euo pipefail

KERNEL="${1:-kernel}"
AUTO_CONF="$KERNEL/techpack/audio/config/sdm450auto.conf"
AUTO_HDR="$KERNEL/techpack/audio/config/sdm450autoconf.h"

test -f "$AUTO_CONF"
test -f "$AUTO_HDR"

disable_auto_conf_symbol() {
  local symbol="$1"
  if grep -qx "${symbol}=y" "$AUTO_CONF"; then
    sed -i "s/^${symbol}=y$/# ${symbol} is not set/" "$AUTO_CONF"
  elif ! grep -qx "# ${symbol} is not set" "$AUTO_CONF"; then
    echo "# ${symbol} is not set" >> "$AUTO_CONF"
  fi
}

disable_auto_header_symbol() {
  local symbol="$1"
  sed -i "/^#define[[:space:]]\+${symbol}[[:space:]]\+1$/d" "$AUTO_HDR"
}

# CLI/headless recovery has no physical HDMI/DP display provider.
# The SDM450 audio auto-profile otherwise compiles the external-display
# codec unconditionally, leaving a reference to msm_ext_disp_* after
# CONFIG_MSM_EXT_DISPLAY is removed.
disable_auto_conf_symbol CONFIG_SND_SOC_MSM_HDMI_CODEC_RX
disable_auto_header_symbol CONFIG_SND_SOC_MSM_HDMI_CODEC_RX

# Legacy AV timer registers callbacks into the camera ISP. With the camera
# stack removed this creates an unresolved msm_isp_set_avtimer_fptr symbol.
# Keep MSM_AVTIMER itself for audio, but remove only the camera-ISP bridge.
disable_auto_conf_symbol CONFIG_AVTIMER_LEGACY
disable_auto_header_symbol CONFIG_AVTIMER_LEGACY

grep -qx '# CONFIG_SND_SOC_MSM_HDMI_CODEC_RX is not set' "$AUTO_CONF"
grep -qx '# CONFIG_AVTIMER_LEGACY is not set' "$AUTO_CONF"
! grep -q '^#define[[:space:]]\+CONFIG_SND_SOC_MSM_HDMI_CODEC_RX[[:space:]]\+1$' "$AUTO_HDR"
! grep -q '^#define[[:space:]]\+CONFIG_AVTIMER_LEGACY[[:space:]]\+1$' "$AUTO_HDR"

echo "Applied Channel CLI-minimal techpack source profile:"
echo "  external-display audio codec: disabled"
echo "  camera ISP AV timer bridge : disabled"
