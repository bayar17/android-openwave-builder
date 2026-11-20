# Build the OpenWave Android images (volunteer guide)

Thank you for helping! OpenWave needs two Android disk images, `system.img` and `vendor.img`, built from
LineageOS 24.0 (Android 17) with the OpenWave changes. One script does everything. It only builds and copies
files; it never changes your system settings and asks before using `sudo`.

**Honest status:** nobody has finished this build yet. The sources, patches and script are checked, but the
Android compile itself has never run to the end, so expect to be the first to find problems. Please send the
logs if something fails.

## What you need

- 64-bit Intel/AMD Linux (Ubuntu, Debian or Fedora), 8+ cores
- 64 GB RAM is ideal. With less, add swap so RAM plus swap is at least 64 GB (the script prints the commands)
- 400 GB free disk on a real Linux filesystem (not tmpfs, NTFS or a container layer)
- Git configured with your name and email, and a stable internet connection (the `repo` tool is bundled in `bin/`)

## Run it

Everything lives in this folder (`fedora-contributor/`): `bin/repo`, `manifests/`, `android/` (patches and device
files), `scripts/`, and `lineage24/`, where the Android source goes (about 130 GB).

```
cd fedora-contributor
source sourceenv.sh                            # puts bin/ on PATH, sets the build environment
scripts/installdep-fedora.sh                   # or installdep-debian.sh; shows what is missing, asks before sudo
scripts/build-android-images.sh preflight      # checks only, changes nothing
scripts/build-android-images.sh                # preflight, sync, build, package
```

Add `--dry-run` to see every step without doing any. If it stops (network, power, Ctrl-C), run the same command
again: finished work is skipped and the sync and build pick up where they stopped. To put the 400 GB somewhere
else, set `OPENWAVE_ANDROID_TREE=/big/disk/dir` before `source sourceenv.sh` (or pass `--tree`). After a build,
`openwave_android_shell` (defined by `sourceenv.sh`) enters the tree with the product selected, for manual `m` runs.

Time: a download of roughly 130 GB, then a build that is likely several hours to a day depending on your
machine. These are estimates; they have not been timed.

## Fedora

The script reads `/etc/os-release` and `scripts/installdep-fedora.sh` prints the exact `dnf install` command for what is missing (run it to be asked, or `--print` / `--check`). These names
were mapped by hand from the Ubuntu list in the LineageOS wiki and are **untested**; if `dnf` reports an unknown
package, tell me which one. Fedora also needs the legacy ncurses and crypt libraries (`ncurses-compat-libs`,
`libxcrypt-compat`; both are in the printed command). Fedora ships a newer glibc and gcc than Google tests, so a
host-tool problem is possible. That is why the script runs the downloaded tools and builds one small module
before the long build starts.

`build-android-images.sh --install-deps` calls the installdep script for you (it still asks before `sudo`). Fedora's
default btrfs root needs `btrfs filesystem mkswapfile` for swap; the script prints the right command.

In a container (podman or docker): keep the source and `out/` on a mounted volume with 400 GB free, not the
container layer. With SELinux enforcing, mount it with the `:Z` label, e.g. `-v /big/disk:/work:Z`.

## What to send back

The script ends by printing a folder like `fedora-contributor/dist/openwave-android-waydroid_x86_64_only-<id>/`. Send:

- `system.img` and `vendor.img`
- `SHA256SUMS` and `build-info.txt` (it also contains your machine details; no personal data)
- if anything failed: `fedora-contributor/out/android-build/runs/latest/results.tsv` and the `*.log` files next to it

## How to check it

```
cd fedora-contributor/dist/openwave-android-*/ && sha256sum -c SHA256SUMS
```

Every line should say `OK`. `build-info.txt` records the exact manifest hash, so two people building the same
version can compare results. The images are raw (not sparse): `system.img` is EROFS and `vendor.img` is ext4;
the script checks both and refuses to package anything else.
