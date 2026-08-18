# Development content

- `Local/Ghosts`: locally acquired ghosts used during development
- `Local/Balloons`: locally acquired balloons used during development
- `Fixtures`: small redistributable data for automated tests
- `Bundled`: content whose license permits bundling with Utatane

`Local` is ignored by Git. Debug builds discover ghosts from `Local/Ghosts`; other builds use `~/Library/Application Support/Utatane/Ghosts`. Set `UTATANE_GHOSTS_ROOT` to override either location.
