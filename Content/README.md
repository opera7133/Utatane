# Development content

- `Local/Ghosts`: locally acquired ghosts used during development
- `Local/Balloons`: locally acquired balloons used during development
- `Fixtures`: small redistributable data for automated tests
- `Bundled`: content whose license permits bundling with Utatane

`Local` is ignored by Git. Debug builds overlay `Bundled` and `Local`, with bundled content taking precedence when directory names overlap. Other builds use `~/Library/Application Support/Utatane`. Set `UTATANE_GHOSTS_ROOT` or `UTATANE_BALLOONS_ROOT` to override the local development roots.

`Bundled` is copied into the app bundle. On first launch, each bundled ghost and balloon is copied to Application Support only when a directory with the same name does not already exist. Existing user content is never overwritten.
