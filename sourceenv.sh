OPENWAVE_KIT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

case ":$PATH:" in
  *":$OPENWAVE_KIT/bin:"*) ;;
  *) export PATH="$OPENWAVE_KIT/bin:$PATH" ;;
esac

openwave_check_dependencies() {
  local id="" like="" key value installer=""
  while IFS='=' read -r key value; do
    value="${value%\"}"
    value="${value#\"}"
    case "$key" in
      ID) id="$value" ;;
      ID_LIKE) like="$value" ;;
    esac
  done <"${OPENWAVE_OS_RELEASE:-/etc/os-release}"
  case " $id $like " in
    *" fedora "*) installer=fedora ;;
    *" ubuntu "*|*" debian "*) installer=debian ;;
  esac
  if [ -z "$installer" ]; then
    printf 'Unsupported OS (%s). Install the packages in scripts/installdep-fedora.sh or installdep-debian.sh by hand.\n' "${id:-unknown}"
    return 1
  fi
  if "$OPENWAVE_KIT/scripts/installdep-$installer.sh" --check >/dev/null 2>&1; then
    printf 'Dependencies are installed. Run scripts/build-android-images.sh\n'
  else
    printf 'Dependencies are not installed. Run installdep-%s.sh\n' "$installer"
    return 1
  fi
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  printf 'source this file instead of running it:  source %s\n' "$0" >&2
  exit 1
fi

openwave_check_dependencies
