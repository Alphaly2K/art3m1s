# Official ANGLE build support

Art3m1s builds ANGLE from the official Chromium ANGLE source at revision
`d9fc4a372074b1079c193c422fc4a180e79b6636` (Chromium 7258).

- Upstream: https://chromium.googlesource.com/angle/angle/
- License: BSD-3-Clause (see the upstream `LICENSE` file)
- Build system: the local vcpkg overlay converts ANGLE's GN source lists to
  CMake using WebKit's `gni-to-cmake.py` helper.

The overlay contains build metadata only. ANGLE source code is downloaded from
the official upstream during the build and is not vendored in this repository.
