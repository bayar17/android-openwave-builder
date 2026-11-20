# OpenWave Waydroid product

Products (each uses the Waydroid board configuration of the device with the same name, so the device names
must stay as they are: `Android.mk` and `BoardConfig.mk` in `device/waydroid/waydroid` only act on
`waydroid_*` devices):

| product | device | notes |
| --- | --- | --- |
| `lineage_openwave_waydroid_x86_64_only` | `waydroid_x86_64_only` | 64-bit only, no VA-API; first test target |
| `lineage_openwave_waydroid_x86_64` | `waydroid_x86_64` | 64 and 32-bit apps, Intel VA-API packages |
| `lineage_openwave_waydroid_arm64` | `waydroid_arm64` | 64 and 32-bit apps |

    source build/envsetup.sh
    lunch lineage_openwave_waydroid_x86_64_only-cp2a-userdebug

Images land in `out/target/product/<device>/` (`system.img`, `vendor.img`).

- `device.mk` is a trimmed copy of Waydroid's `device.mk`: no ATV, GApps, Widevine, native bridge or updater.
- `remove_packages/Android.mk` lists the packages removed with `LOCAL_OVERRIDES_PACKAGES`, because a product
  cannot remove packages that an inherited makefile adds.
- `overlay/` holds the framework, SystemUI, SettingsProvider and Settings resources: centered Back-only
  navigation bar, wallpaper service and dreams off, lock screen off, heads-up popups off, a hidden status bar
  window (`config_hideStatusBarWindow`, added by a frameworks/base patch) and default disable flags that keep the
  shade and Quick Settings closed. The status bar height is left alone so the privacy dots keep working.
- `overlay/packages/apps/Settings/res/xml/top_level_settings*.xml` are generated: rerun
  `python3 device/openwave/waydroid/tools/gen_settings_overlay.py` after every Settings update.
- `tinh/` is the prebuilt TINH Home app (`TINH.apk`, release-signed) and its privapp permission allowlist. It
  installs at `/system/priv-app/TINH/TINH.apk`, the same path OpenWave's host overlay uses, so the host copy
  takes over when it is present. Refresh it by copying `userspace/waydroid/NoLauncher/TINH.apk` from the
  OpenWave tree.
