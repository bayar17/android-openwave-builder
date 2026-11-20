#!/usr/bin/env bash

OPENWAVE_APT_PKGS=(bc bison build-essential ccache curl erofs-utils flex g++-multilib gcc-multilib git git-lfs gnupg
  gperf imagemagick kmod libdw-dev libelf-dev libgnutls28-dev lib32readline-dev lib32z1-dev libsdl1.2-dev
  libssl-dev libxml2 libxml2-utils lz4 lzop pngcrush protobuf-compiler python3 python3-protobuf rsync schedtool
  squashfs-tools xsltproc xxd yasm zip unzip zlib1g-dev meson glslang-tools python3-mako)

openwave_apt_list() {
  local os_id="" os_version="" key value wanted
  while IFS='=' read -r key value; do
    value="${value%\"}"
    value="${value#\"}"
    case "$key" in
      ID) os_id="$value" ;;
      VERSION_ID) os_version="$value" ;;
    esac
  done <"${OPENWAVE_OS_RELEASE:-/etc/os-release}"
  for wanted in "${OPENWAVE_APT_PKGS[@]}"; do
    if [ "$wanted" = libxml2 ] && [ "$os_id" = ubuntu ] && [ "$(printf '%s\n26.04\n' "${os_version:-0}" | sort -V | head -n 1)" = 26.04 ]; then
      wanted=libxml2-16
    fi
    printf '%s\n' "$wanted"
  done
}

openwave_missing_packages() {
  local p
  while IFS= read -r p; do
    [ "$(dpkg-query -W -f='${db:Status-Abbrev}' "$p" 2>/dev/null)" = "ii " ] || printf '%s\n' "$p"
  done < <(openwave_apt_list)
}

openwave_install_command() {
  printf 'sudo apt-get install -y'
  printf ' %s' "$@"
  printf '\n'
}

openwave_installdep_main() {
  local missing=() all=() answer=""
  case "${1:-}" in
    -h|--help)
      printf 'usage: %s [--check | --print | --list]\n' "$(basename "$0")"
      printf '  (no option)  show what is missing, ask, then run the apt-get command with sudo\n'
      printf '  --check      exit 0 when everything is installed, 1 when something is missing\n'
      printf '  --print      print the apt-get command without running it\n'
      printf '  --list       print the full package list\n'
      printf 'The list comes from the LineageOS wiki (Ubuntu); other Debian-based systems are UNVERIFIED.\n'
      return 0
      ;;
    --list)
      openwave_apt_list
      return 0
      ;;
  esac
  if ! command -v dpkg-query >/dev/null 2>&1 || ! command -v apt-get >/dev/null 2>&1; then
    printf 'dpkg and apt-get are required; this script is for Debian and Ubuntu (see installdep-fedora.sh for Fedora)\n' >&2
    return 2
  fi
  mapfile -t all < <(openwave_apt_list)
  mapfile -t missing < <(openwave_missing_packages)
  if [ "${#missing[@]}" -eq 0 ]; then
    printf 'all %s packages are installed\n' "${#all[@]}"
    return 0
  fi
  printf '%s of %s packages are missing:\n  %s\n\n' "${#missing[@]}" "${#all[@]}" "${missing[*]}"
  openwave_install_command "${missing[@]}"
  case "${1:-}" in
    --check) return 1 ;;
    --print) return 1 ;;
  esac
  [ -r /dev/tty ] || { printf 'no terminal to ask on; run the command above yourself\n'; return 1; }
  printf '\nRun it now with sudo? [y/N] ' >/dev/tty
  read -r answer </dev/tty || return 1
  case "$answer" in
    y|Y|yes) sudo apt-get install -y "${missing[@]}" ;;
    *) printf 'nothing installed\n'; return 1 ;;
  esac
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  openwave_installdep_main "$@"
  exit $?
fi
