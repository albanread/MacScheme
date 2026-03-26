# MacScheme v0.1.0

Initial local baseline release for the `chezmac` repository.

## Highlights

- Adds the first committed MacScheme app baseline with editor, REPL, Cocoa app shell, graphics/runtime bridge, and required build assets.
- Includes the required Chez runtime artifacts for local build and app startup:
  - `MacScheme/lib/libkernel.a`
  - `MacScheme/lib/liblz4.a`
  - `MacScheme/lib/libz.a`
  - `MacScheme/resources/petite.boot`
  - `MacScheme/resources/scheme.boot`
- Documents the Chez/runtime boundary in `chez_linked.md`.
- Adds helper scripts:
  - `run.sh` to build and launch the app from the repo root
  - `package.sh` to create a distributable macOS app bundle and zip archive
- Fixes runtime boot-file lookup so the packaged app loads resources from the bundle, with a development fallback to the source tree.

## Included commits

- `96fd902` Initial MacScheme editor app baseline
- `f9311c2` Add run and packaging scripts

## Notes

- Current tag: `v0.1.0`
- Packaging output is generated under `dist/` and ignored by Git.
