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
