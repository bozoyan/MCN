# FJS upstream

- Repository: https://github.com/fluttercandies/fjs
- Version / tag: 3.3.1 / v3.3.1
- Commit: `e911656369fd303754beabe1ec7f2eca0e47b05c`
- Release archive: https://pub.dev/api/archives/fjs-3.3.1.tar.gz
- Archive SHA-256: `c96babc2c3b13ca1c55b55cc91141e1c34fd6cf885094683414200efc02598d2`
- Imported on: 2026-09-30

The initial import preserves every release-archive file byte-for-byte except
`darwin/fjs/Binaries/fjs.xcframework.zip`. That upstream precompiled archive
must never be used: build it from the patched source before building Apple apps.
The import includes upstream Dart/Rust generated sources, native build scripts,
Cargo.lock, CargoKit source and lockfile, tests, examples and the MIT license.
There is no submodule or downloaded native artifact in the source history.

Local changes are documented in `fjs/REVERIC_PATCH.md`; Git commits are the
patch source of truth. Upgrades must preserve the Dart/Rust bridge version match,
reapply the loader restriction and the optional builtin removal, and rerun real native boundary/bridge/cancellation
tests plus platform build and app loading checks. Do not follow upstream main.
