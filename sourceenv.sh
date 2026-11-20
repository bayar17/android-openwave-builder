OPENWAVE_KIT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export OPENWAVE_KIT

case ":$PATH:" in
  *":$OPENWAVE_KIT/bin:"*) ;;
  *) export PATH="$OPENWAVE_KIT/bin:$PATH" ;;
esac

export OPENWAVE_ANDROID_TREE="${OPENWAVE_ANDROID_TREE:-$OPENWAVE_KIT/lineage24}"
export OPENWAVE_ANDROID_WORK="${OPENWAVE_ANDROID_WORK:-$OPENWAVE_KIT/out/android-build}"
export OPENWAVE_ANDROID_DIST="${OPENWAVE_ANDROID_DIST:-$OPENWAVE_KIT/dist}"

export OPENWAVE_LUNCH_TARGET="lineage_openwave_waydroid_x86_64_only-cp2a-userdebug"
export OPENWAVE_BUILD_NUMBER="openwave.1"
export OPENWAVE_BUILD_DATETIME="1700000000"
export OPENWAVE_BUILD_DATE="20231114"
export OPENWAVE_BUILD_USERNAME="openwave"
export OPENWAVE_BUILD_HOSTNAME="openwave-build"

export LC_ALL=C
export TZ=UTC
export SOONG_NINJA=ninja
unset OUT_DIR OUT_DIR_COMMON_BASE

openwave_android_shell() {
  if [ ! -f "$OPENWAVE_ANDROID_TREE/build/envsetup.sh" ]; then
    printf 'no synced tree at %s; run scripts/build-android-images.sh sync first\n' "$OPENWAVE_ANDROID_TREE" >&2
    return 1
  fi
  cd "$OPENWAVE_ANDROID_TREE" || return 1
  export BUILD_NUMBER="$OPENWAVE_BUILD_NUMBER" BUILD_DATETIME="$OPENWAVE_BUILD_DATETIME"
  export BUILD_USERNAME="$OPENWAVE_BUILD_USERNAME" BUILD_HOSTNAME="$OPENWAVE_BUILD_HOSTNAME"
  source build/envsetup.sh >/dev/null && lunch "$OPENWAVE_LUNCH_TARGET"
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  printf 'source this file instead of running it:  source %s\n' "$0" >&2
  exit 1
fi

[ -n "${OPENWAVE_QUIET:-}" ] || printf 'OpenWave kit: %s\n  repo: %s (%s)\n  tree: %s\n  openwave_android_shell  enters the tree with the product selected\n' \
  "$OPENWAVE_KIT" "$(command -v repo)" "$(repo --version 2>/dev/null | grep -m1 'launcher version')" "$OPENWAVE_ANDROID_TREE"
