# Embedded YAYA

This target uses the [`utatane-macos` branch of the YAYA fork](https://github.com/opera7133/yaya-shiori/tree/utatane-macos)
as the `Vendor/YAYA` git submodule. It is based on the upstream `500` branch
(`f64a42d`, tag `Tc573-6`). The upstream implementation is distributed under
the BSD 3-Clause License; its license is preserved in the submodule.

The fork keeps the original evaluator and POSIX SHIORI implementation. Local
changes are intentionally limited to modern macOS compilation, standard C++
smart pointers, fixed-width integer declarations, Darwin macro conflicts, and
request-buffer ownership. `YayaBridge.cpp` exposes a small C ABI to Swift.

Windows-only FMO and DLL loading remain unavailable on macOS.
