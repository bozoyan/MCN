# Local changes

Source: published `irondash_engine_context 0.6.0-dev.0` from https://pub.dev/packages/irondash_engine_context/versions/0.6.0-dev.0.

- Upgrade the build dependency to `code_assets ^2.0.0` and `native_toolchain_rust ^1.0.7`. The Android hook uses `buildCodeAssets`, `config.code.targetOS` and `OS.android`; verify these APIs with the locked SDK during builds.
- Keep all platform source and runtime APIs unchanged. Remove the override when upstream publishes compatible constraints.
