# OpenWave Android build

Thanks for helping out. This folder builds two Android images for OpenWave, `system.img` and `vendor.img`.
It needs a 64-bit Linux machine (Fedora, Ubuntu or Debian) with about 64 GB of RAM (swap counts) and 400 GB of free disk.
It takes a long time, so start it and leave it alone.

Nobody has finished this build yet, so if it stops with an error, that is useful news. Send me the log.

## Run it

```
cd fedora-contributor
source sourceenv.sh
```

If it says the dependencies are not installed, run the script it names (`scripts/installdep-fedora.sh` or
`scripts/installdep-debian.sh`). It asks before using sudo. Then:

```
scripts/build-android-images.sh
```

If it stops for any reason, run the same command again and it carries on.

## When it finishes

It prints a folder under `dist/`. Send me that folder. If it failed, send `out/android-build/runs/latest/`.
