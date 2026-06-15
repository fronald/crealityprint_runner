# CrealityPrint on Fedora

Launcher script that makes the [CrealityPrint](https://github.com/CrealityOfficial/CrealityPrint) AppImage run on Fedora.

Fixes two upstream bugs:

- `AppRun` overwrites `LD_LIBRARY_PATH` without preserving the caller's value ([PR #539](https://github.com/CrealityOfficial/CrealityPrint/pull/539))
- Missing libs not bundled in the AppImage (e.g. `libbz2.so.1.0`)

## Usage

1. Download a `CrealityPrint*.appimage` into this directory.
2. Run:

```bash
./run-crealityprint.sh
```

First run extracts the AppImage and applies the patches. Subsequent runs start directly.

To re-extract after updating the AppImage:

```bash
rm -rf squashfs-root
```
