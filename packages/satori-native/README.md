# Embedded SATORI

This target uses the `satoriya` subtree from the
[`utatane-vendor` branch of the SATORI fork](https://github.com/opera7133/satoriya-shiori/tree/utatane-vendor)
as the `Sources/CSatoriNative/Vendor` git submodule. Keeping the subtree at the
submodule root preserves the original `Vendor/_` and `Vendor/satori` include
layout.

The fork contains the small POSIX compatibility changes needed to compile the
original SATORI implementation on macOS. `SatoriBridge.cpp`, `CharsetPOSIX.cpp`,
and the Swift adapter remain in Utatane.
