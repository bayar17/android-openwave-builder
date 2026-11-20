#!/usr/bin/env bash

OPENWAVE_DNF_PKGS=(bc bison ccache curl diffutils elfutils-devel elfutils-libelf-devel erofs-utils flex gcc gcc-c++ git
  git-lfs glibc-devel.i686 glslang gnupg2 gnutls-devel gperf ImageMagick kmod libstdc++-devel.i686
  libxcrypt-compat libxslt lz4 make meson ncurses-compat-libs ncurses-devel openssl-devel patch perl pngcrush
  protobuf-compiler python3 python3-mako python3-protobuf rsync schedtool squashfs-tools unzip which zip
  /usr/bin/hostname /usr/bin/xmllint /usr/bin/xxd /usr/lib/libz.so /usr/lib/libreadline.so)

openwave_missing_packages() {
  local p
  for p in "${OPENWAVE_DNF_PKGS[@]}"; do
    rpm -q --whatprovides "$p" >/dev/null 2>&1 || printf '%s\n' "$p"
  done
}

openwave_install_command() {
  printf 'sudo dnf install -y'
  printf ' %s' "$@"
  printf '\n'
}

openwave_installdep_main() {
  local missing=() answer=""
  case "${1:-}" in
    -h|--help)
      printf 'usage: %s [--check | --print | --list]\n' "$(basename "$0")"
      printf '  (no option)  show what is missing, ask, then run the dnf command with sudo\n'
      printf '  --check      exit 0 when everything is installed, 1 when something is missing\n'
      printf '  --print      print the dnf command without running it\n'
      printf '  --list       print the full package list\n'
      printf 'Fedora package names are mapped by hand from the Ubuntu list in the LineageOS wiki (UNVERIFIED).\n'
      return 0
      ;;
    --list)
      printf '%s\n' "${OPENWAVE_DNF_PKGS[@]}"
      return 0
      ;;
  esac
  if ! command -v rpm >/dev/null 2>&1 || ! command -v dnf >/dev/null 2>&1; then
    printf 'rpm and dnf are required; this script is for Fedora (see installdep-debian.sh for Debian and Ubuntu)\n' >&2
    return 2
  fi
  mapfile -t missing < <(openwave_missing_packages)
  if [ "${#missing[@]}" -eq 0 ]; then
    printf 'all %s packages are installed\n' "${#OPENWAVE_DNF_PKGS[@]}"
    return 0
  fi
  printf '%s of %s packages are missing:\n  %s\n\n' "${#missing[@]}" "${#OPENWAVE_DNF_PKGS[@]}" "${missing[*]}"
  openwave_install_command "${missing[@]}"
  case "${1:-}" in
    --check) return 1 ;;
    --print) return 1 ;;
  esac
  [ -r /dev/tty ] || { printf 'no terminal to ask on; run the command above yourself\n'; return 1; }
  printf '\nRun it now with sudo? [y/N] ' >/dev/tty
  read -r answer </dev/tty || return 1
  case "$answer" in
    y|Y|yes) sudo dnf install -y "${missing[@]}" ;;
    *) printf 'nothing installed\n'; return 1 ;;
  esac
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  openwave_installdep_main "$@"
  exit $?
fi
