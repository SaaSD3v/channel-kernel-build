# Direct GPU in DroidSpaces — Channel / Adreno 506

This records real-device validation of direct container GPU access on Motorola Moto G7 Play (`channel`).

## Scope

"Direct GPU" means the Linux container opens Qualcomm KGSL through DroidSpaces GPU-only device mirroring and uses Mesa Freedreno's KGSL KMD backend.

It does **not** use VirGL, virpipe, a vtest socket, or direct userspace MMIO.

Validated device:

- Motorola Moto G7 Play (`channel`)
- kernel `4.9.206-perf+`
- Adreno 506
- DroidSpaces v6.6.0
- `/dev/kgsl-3d0`
- `/dev/ion`

## Architecture

```text
OpenGL / OpenGL ES application
            |
            v
Mesa 26.3-devel
            |
            v
Gallium Freedreno (FD506)
            |
            v
Freedreno KGSL KMD
            |
            v
/dev/kgsl-3d0 + /dev/ion
            |
            v
KGSL 4.9 / Adreno 506
```

VirGL remains a separate path and must not be conflated with this one.

## DroidSpaces mode

The validated configuration is:

```ini
enable_hw_access=0
enable_gpu_mode=1
```

DroidSpaces reports:

```text
HW access: GPU
```

This keeps an isolated container `/dev` while exposing GPU-related nodes.

On this recovery/kernel combination, Alpine userspace reports character-device `st_rdev` as `0:0` even for ordinary nodes such as `/dev/null` and `/dev/zero`. Do not use that output to identify KGSL here.

Kernel interfaces correctly report:

```text
/proc/devices: 238 kgsl
/sys/class/kgsl/kgsl-3d0/dev=238:0
/sys/class/kgsl/kgsl-3d0/gpu_model=Adreno506v1
```

## Mesa runtime used for validation

The working userspace was isolated under `/opt`:

- `lfdevs/mesa-for-android-container`
- release `mesa-26.3.0-devel-20260824`
- Alpine 3.24 arm64 tarball extracted under `/opt/mesa-kgsl-test`
- `llvm22-libs-22.1.3-r0` extracted under `/opt/llvm22-test`
- test rootfs: Alpine 3.23

Nothing was overwritten in `/usr`.

Runtime variables:

```sh
LLVM_LIB=/opt/llvm22-test/usr/lib
MESA_LIB=/opt/mesa-kgsl-test/usr/lib
DRI=/opt/mesa-kgsl-test/usr/lib/dri

export LD_LIBRARY_PATH="$LLVM_LIB:$MESA_LIB"
export LIBGL_DRIVERS_PATH="$DRI"
export MESA_LOADER_DRIVER_OVERRIDE=kgsl
```

## Debian / GLVND note

On Debian 13, setting only `LD_LIBRARY_PATH`, `LIBGL_DRIVERS_PATH`, and `MESA_LOADER_DRIVER_OVERRIDE=kgsl` is not sufficient when the system GLVND dispatcher still selects Debian's stock Mesa vendor library. In that case the test can render correctly with llvmpipe while never loading the custom KGSL Mesa.

Force the custom EGL vendor JSON from the extracted tarball:

```sh
MESA_ROOT=/opt/mesa-kgsl-test/usr
MESA_LIB="$MESA_ROOT/lib/aarch64-linux-gnu"
DRI="$MESA_LIB/dri"
EGL_VENDOR="$MESA_ROOT/share/glvnd/egl_vendor.d/50_mesa.json"

export LD_LIBRARY_PATH="$MESA_LIB"
export LIBGL_DRIVERS_PATH="$DRI"
export MESA_LOADER_DRIVER_OVERRIDE=kgsl
export __EGL_VENDOR_LIBRARY_FILENAMES="$EGL_VENDOR"
```

A valid direct test must report both `GL_VENDOR=freedreno` and `GL_RENDERER=FD506`. The repository render test enforces those values and fails with `NOT_DIRECT_KGSL_RENDERER` otherwise.

## Proven renderer

`eglinfo -B -p surfaceless` returned Freedreno directly:

```text
OpenGL core profile vendor: freedreno
OpenGL core profile renderer: FD506
OpenGL ES profile vendor: freedreno
OpenGL ES profile renderer: FD506
OpenGL ES profile version: OpenGL ES 3.1 Mesa 26.3.0-devel
```

## Render/readback validation

`gpu/direct_kgsl_render_test.c` creates a surfaceless EGL display, ES2 pbuffer/context, clears a 16x16 framebuffer, waits, then reads one RGBA pixel back.

Real-device result:

```text
EGL=1.5
GL_VENDOR=freedreno
GL_RENDERER=FD506
GL_VERSION=OpenGL ES 3.1 Mesa 26.3.0-devel
PIXEL=64,128,191,255
GL_ERROR=0x0
DIRECT_KGSL_RENDER_OK
```

Exit code: `0`.

Compile inside a container with EGL/GLES development headers:

```sh
cc -O2 gpu/direct_kgsl_render_test.c \
  -o /tmp/kgsl_render_test \
  -L"$MESA_LIB" \
  -Wl,-rpath,"$MESA_LIB" \
  -lEGL -lGLESv2
```

Run:

```sh
LD_LIBRARY_PATH="$LLVM_LIB:$MESA_LIB" \
LIBGL_DRIVERS_PATH="$DRI" \
MESA_LOADER_DRIVER_OVERRIDE=kgsl \
/tmp/kgsl_render_test
```

## Stability results

Real-device tests passed:

- 4 simultaneous clients: 4/4
- sequential loop: 50/50
- concurrent stress: 4 workers x 10 = 40/40
- every recorded renderer: `FD506`
- every readback: expected pixel
- no filtered KGSL/Adreno fault, hang, timeout, reset, IOMMU fault, BUG or Oops after the stress run

Observed idle clock after the short tests was 320 MHz; sysfs max was 725 MHz. This validation is functional/stability validation, not a performance benchmark.

## Known warnings

Mesa may print:

```text
MESA-LOADER: failed to retrieve device information
```

The generic loader attempts DRM-style device discovery; KGSL still initializes and renders as FD506.

Kernel 4.9 may also cause:

```text
os_same_file_description couldn't determine if two DRM fds reference the same file description. (Function not implemented)
```

Mesa has a fallback for this case. The warning was present during successful render/readback and stress testing.

## Project boundary

Keep responsibilities separate:

- recovery/kernel: preserve working KGSL, ION, firmware and Adreno hardware path
- DroidSpaces: mirror GPU nodes into isolated `/dev` when GPU mode is enabled
- container userspace: provide/select Mesa Freedreno KGSL and dependencies
- RCTools VirGL: optional host VirGL lifecycle only

RCTools must not choose container Mesa backends or inject distro-specific Mesa environment variables.
