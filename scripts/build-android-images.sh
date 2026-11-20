#!/usr/bin/env bash
set -uo pipefail

SCRIPT_VERSION="1"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KIT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SELF="$SCRIPT_DIR/$(basename "${BASH_SOURCE[0]}")"

OPENWAVE_QUIET=1 source "$KIT_ROOT/sourceenv.sh"

WORK_DIR="$OPENWAVE_ANDROID_WORK"
TREE="$OPENWAVE_ANDROID_TREE"
DIST_DIR="$OPENWAVE_ANDROID_DIST"

PRODUCT="lineage_openwave_waydroid_x86_64_only"
DEVICE="waydroid_x86_64_only"
LUNCH_TARGET="$OPENWAVE_LUNCH_TARGET"
MANIFEST_BRANCH="lineage-24.0 (android-17.0.0_r1)"

BUILD_NUMBER_FIXED="$OPENWAVE_BUILD_NUMBER"
BUILD_DATETIME_FIXED="$OPENWAVE_BUILD_DATETIME"
BUILD_DATE_FIXED="$OPENWAVE_BUILD_DATE"
BUILD_USERNAME_FIXED="$OPENWAVE_BUILD_USERNAME"
BUILD_HOSTNAME_FIXED="$OPENWAVE_BUILD_HOSTNAME"

MIN_FREE_GIB_FRESH=400
MIN_FREE_GIB_RESUME=200
MIN_FREE_GIB_BUILD=120
RECOMMENDED_MEM_GIB=64
MIN_MEM_GIB=48
GIB_PER_JOB=2

COMMAND="all"
DRY_RUN=0
JOBS=""
SYNC_JOBS=8
DEPTH=1
MIN_DISK_GIB=""
ALLOW_LOW_MEMORY=0
INSTALL_DEPS=0

OS_ID=""
OS_LIKE=""
OS_VERSION=""
OS_PRETTY=""
OS_FAMILY="other"
CONTAINER=""
COUNT_PASS=0
COUNT_FAIL=0
COUNT_BLOCKED=0
COUNT_UNVERIFIED=0
LAST_LOG=""

usage() {
  cat <<EOF
OpenWave Android image build kit (script version $SCRIPT_VERSION)

usage: $(basename "$SELF") [command] [options]

commands:
  preflight   check this machine, change nothing
  sync        fetch the pinned sources, add the OpenWave product and patches
  build       build system.img and vendor.img
  package     copy the images to dist/ with checksums and build-info.txt
  all         preflight, sync, build, package (default)

options:
  --dry-run            print what would run; nothing is created, fetched or built
  --tree DIR           where the Android source tree lives (default: lineage24/ in this folder)
  --dist DIR           where package writes its output (default: dist/ in this folder)
  --jobs N             parallel build jobs (default: from available RAM)
  --sync-jobs N        parallel fetches for repo sync (default $SYNC_JOBS)
  --depth N            repo clone depth, 0 for full history (default $DEPTH)
  --min-disk-gb N      override the free-disk requirement
  --allow-low-memory   continue when RAM+swap is below $RECOMMENDED_MEM_GIB GiB
  --install-deps       offer to run the package install command (asks before sudo)
  -h, --help           this text

Every command can be run again; finished work is detected and skipped.
Evidence for each run is written to fedora-contributor/out/android-build/runs/<timestamp>/ (results.tsv and logs).
EOF
}

while [ $# -gt 0 ]; do
  case "$1" in
    preflight|sync|build|package|all) COMMAND="$1" ;;
    --dry-run) DRY_RUN=1 ;;
    --tree) shift; TREE="${1:?--tree needs a directory}" ;;
    --dist) shift; DIST_DIR="${1:?--dist needs a directory}" ;;
    --jobs) shift; JOBS="${1:?--jobs needs a number}" ;;
    --sync-jobs) shift; SYNC_JOBS="${1:?--sync-jobs needs a number}" ;;
    --depth) shift; DEPTH="${1:?--depth needs a number}" ;;
    --min-disk-gb) shift; MIN_DISK_GIB="${1:?--min-disk-gb needs a number}" ;;
    --allow-low-memory) ALLOW_LOW_MEMORY=1 ;;
    --install-deps) INSTALL_DEPS=1 ;;
    -h|--help) usage; exit 0 ;;
    *) printf 'unknown argument: %s\n\n' "$1" >&2; usage >&2; exit 64 ;;
  esac
  shift
done

case "$TREE" in /*) ;; *) TREE="$PWD/$TREE" ;; esac
case "$DIST_DIR" in /*) ;; *) DIST_DIR="$PWD/$DIST_DIR" ;; esac

RUN_ID="$(date -u +%Y%m%dT%H%M%SZ)-$COMMAND"
[ "$DRY_RUN" = 1 ] && RUN_ID="$RUN_ID-dryrun"
RUN_DIR="$WORK_DIR/runs/$RUN_ID"
RESULTS="$RUN_DIR/results.tsv"
mkdir -p "$RUN_DIR" || { printf 'cannot create %s\n' "$RUN_DIR" >&2; exit 70; }
printf 'time\tstep\tstatus\tdetail\tevidence\n' >"$RESULTS"
ln -sfn "$RUN_DIR" "$WORK_DIR/runs/latest"

record() {
  local step="$1" status="$2" detail="$3" evidence="${4:--}"
  printf '%s\t%s\t%s\t%s\t%s\n' "$(date -u +%H:%M:%S)" "$step" "$status" "$detail" "$evidence" >>"$RESULTS"
  printf '%-12s %-26s %s\n' "[$status]" "$step" "$detail"
  if [ "$evidence" != "-" ]; then
    printf '%-12s %-26s   evidence: %s\n' "" "" "$evidence"
  fi
  case "$status" in
    PASS) COUNT_PASS=$((COUNT_PASS + 1)) ;;
    FAIL) COUNT_FAIL=$((COUNT_FAIL + 1)) ;;
    BLOCKED) COUNT_BLOCKED=$((COUNT_BLOCKED + 1)) ;;
    *) COUNT_UNVERIFIED=$((COUNT_UNVERIFIED + 1)) ;;
  esac
}

have_problem() {
  [ $((COUNT_FAIL + COUNT_BLOCKED)) -gt 0 ]
}

quote_cmd() {
  printf '%q ' "$@"
}

run_logged() {
  local name="$1" description="$2"
  shift 2
  LAST_LOG="$RUN_DIR/$name.log"
  if [ "$DRY_RUN" = 1 ]; then
    printf 'DRY-RUN %-18s %s\n' "$name" "$description"
    return 0
  fi
  printf '+ %s\n' "$description" >"$LAST_LOG"
  printf '+ %s\n' "$description"
  "$@" 2>&1 | tee -a "$LAST_LOG"
  return "${PIPESTATUS[0]}"
}

finish() {
  local step="$1" rc="$2" ok="$3" bad="$4"
  if [ "$DRY_RUN" = 1 ]; then
    record "$step" UNVERIFIED "dry run, not executed: $ok" -
  elif [ "$rc" = 0 ]; then
    record "$step" PASS "$ok" "$LAST_LOG"
  else
    record "$step" FAIL "$bad (exit $rc)" "$LAST_LOG"
  fi
  return "$rc"
}

confirm() {
  local answer=""
  [ "$DRY_RUN" = 1 ] && return 1
  [ -r /dev/tty ] || return 1
  printf '%s [y/N] ' "$1" >/dev/tty
  read -r answer </dev/tty || return 1
  [ "$answer" = y ] || [ "$answer" = Y ] || [ "$answer" = yes ]
}

ver_ge() {
  [ "$(printf '%s\n%s\n' "$2" "$1" | sort -V | head -n 1)" = "$2" ]
}

existing_ancestor() {
  local p="$1"
  while [ ! -d "$p" ]; do
    p="$(dirname "$p")"
  done
  printf '%s\n' "$p"
}

fs_type() {
  findmnt -n -o FSTYPE -T "$1" 2>/dev/null | head -n 1 || stat -f -c %T "$1" 2>/dev/null
}

free_gib() {
  local kib
  kib="$(df -Pk "$1" 2>/dev/null | awk 'NR==2 {print $4}')"
  printf '%s\n' $(( ${kib:-0} / 1048576 ))
}

load_os_release() {
  local key value
  [ -r "${OPENWAVE_OS_RELEASE:-/etc/os-release}" ] || return 1
  while IFS='=' read -r key value; do
    value="${value%\"}"
    value="${value#\"}"
    case "$key" in
      ID) OS_ID="$value" ;;
      ID_LIKE) OS_LIKE="$value" ;;
      VERSION_ID) OS_VERSION="$value" ;;
      PRETTY_NAME) OS_PRETTY="$value" ;;
    esac
  done <"${OPENWAVE_OS_RELEASE:-/etc/os-release}"
  case " $OS_ID $OS_LIKE " in
    *" fedora "*) OS_FAMILY=fedora ;;
    *" ubuntu "*|*" debian "*) OS_FAMILY=debian ;;
  esac
  return 0
}

detect_container() {
  if [ -f /run/.containerenv ]; then
    CONTAINER=podman
  elif [ -f /.dockerenv ]; then
    CONTAINER=docker
  elif command -v systemd-detect-virt >/dev/null 2>&1 && systemd-detect-virt -cq 2>/dev/null; then
    CONTAINER="$(systemd-detect-virt -c 2>/dev/null)"
  elif grep -qaE 'docker|podman|libpod|lxc|containerd' /proc/1/cgroup 2>/dev/null; then
    CONTAINER=container
  fi
}

mem_kib() {
  awk -v key="$1:" '$1 == key {print $2}' /proc/meminfo
}

swap_kib_real() {
  awk 'NR > 1 && $1 !~ /zram/ {sum += $3} END {print sum + 0}' /proc/swaps
}

swap_kib_zram() {
  awk 'NR > 1 && $1 ~ /zram/ {sum += $3} END {print sum + 0}' /proc/swaps
}

compute_jobs() {
  local ram_gib cores j
  if [ -n "$JOBS" ]; then
    return 0
  fi
  ram_gib=$(( $(mem_kib MemTotal) / 1048576 ))
  cores="$(nproc 2>/dev/null || echo 1)"
  j=$(( ram_gib / GIB_PER_JOB ))
  [ "$j" -gt "$cores" ] && j="$cores"
  [ "$j" -lt 1 ] && j=1
  JOBS="$j"
}

manifest_hash() {
  cat "$KIT_ROOT/manifests/default.xml" "$KIT_ROOT/manifests/local_manifests/openwave.xml" | sha256sum | cut -d' ' -f1
}

host_info() {
  local file="$RUN_DIR/host-info.txt"
  {
    printf 'script_version=%s\n' "$SCRIPT_VERSION"
    printf 'date_utc=%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    printf 'uname=%s\n' "$(uname -a)"
    printf 'os=%s\n' "${OS_PRETTY:-unknown}"
    printf 'glibc=%s\n' "$(getconf GNU_LIBC_VERSION 2>/dev/null)"
    printf 'gcc=%s\n' "$(gcc --version 2>/dev/null | head -n 1)"
    printf 'python3=%s\n' "$(python3 --version 2>&1)"
    printf 'git=%s\n' "$(git --version 2>&1)"
    printf 'cpu_model=%s\n' "$(awk -F': ' '/model name/ {print $2; exit}' /proc/cpuinfo)"
    printf 'cpu_threads=%s\n' "$(nproc 2>/dev/null)"
    printf 'mem_total_kib=%s\n' "$(mem_kib MemTotal)"
    printf 'swap_real_kib=%s\n' "$(swap_kib_real)"
    printf 'swap_zram_kib=%s\n' "$(swap_kib_zram)"
    printf 'container=%s\n' "${CONTAINER:-none}"
  } >"$file"
  printf '%s\n' "$file"
}

pf_arch() {
  local m
  m="$(uname -m)"
  if [ "$m" = x86_64 ]; then
    record preflight.arch PASS "x86_64"
  else
    record preflight.arch FAIL "host is $m; the Android host prebuilts are x86_64 only"
  fi
}

pf_os() {
  if ! load_os_release; then
    record preflight.os UNVERIFIED "no /etc/os-release; cannot choose a package manager"
    return
  fi
  case "$OS_FAMILY" in
    debian)
      record preflight.os PASS "$OS_PRETTY (apt); package list taken from the LineageOS wiki, which tests Ubuntu 20.04"
      ;;
    fedora)
      record preflight.os UNVERIFIED "$OS_PRETTY (dnf); Fedora is not a host Google or LineageOS test, package names are mapped by hand"
      ;;
    *)
      record preflight.os UNVERIFIED "$OS_PRETTY: no package list for this distribution, only generic checks run"
      ;;
  esac
}

pf_container() {
  detect_container
  if [ -z "$CONTAINER" ]; then
    record preflight.container PASS "not running in a container"
    return
  fi
  local note="running in $CONTAINER; source and out/ must be on a mounted volume with enough free space, not the container layer"
  if [ -r /sys/fs/selinux/enforce ] && [ "$(cat /sys/fs/selinux/enforce 2>/dev/null)" = 1 ]; then
    note="$note; SELinux is enforcing on the host, start the container with the volume mounted as -v HOSTDIR:/work:Z (podman or docker)"
  fi
  record preflight.container UNVERIFIED "$note"
}

pf_glibc() {
  local v
  v="$(getconf GNU_LIBC_VERSION 2>/dev/null | awk '{print $2}')"
  if [ -z "$v" ]; then
    record preflight.glibc FAIL "cannot read the glibc version; the Android host prebuilts need glibc"
  elif ver_ge "$v" 2.31; then
    record preflight.glibc PASS "glibc $v"
  else
    record preflight.glibc FAIL "glibc $v is older than 2.31"
  fi
}

pf_compiler() {
  local v
  v="$(gcc --version 2>/dev/null | head -n 1)"
  if [ -z "$v" ]; then
    record preflight.compiler BLOCKED "gcc not found; install the packages listed by preflight.packages"
  else
    record preflight.compiler PASS "$v (Android builds its tools with its own prebuilt clang; the system gcc is only used for a few host-side parts)"
  fi
}

pf_cpu() {
  local flags missing="" f cores
  flags="$(awk -F': ' '/^flags/ {print $2; exit}' /proc/cpuinfo)"
  for f in sse4_2 popcnt ssse3; do
    case " $flags " in *" $f "*) ;; *) missing="$missing $f" ;; esac
  done
  cores="$(nproc 2>/dev/null || echo 1)"
  if [ -n "$missing" ]; then
    record preflight.cpu BLOCKED "CPU lacks:$missing; the prebuilt host tools may crash with illegal instruction"
    return
  fi
  case " $flags " in
    *" avx2 "*) record preflight.cpu PASS "$cores threads; sse4_2 popcnt ssse3 avx2 present" ;;
    *) record preflight.cpu UNVERIFIED "$cores threads; sse4_2 popcnt ssse3 present but avx2 missing, the post-sync tool smoke test decides" ;;
  esac
  if [ "$cores" -lt 4 ]; then
    record preflight.cores UNVERIFIED "only $cores threads; the build will take very long"
  fi
}

pf_memory() {
  local ram_kib swap_kib zram_kib ram_gib swap_gib total_gib need fstype
  ram_kib="$(mem_kib MemTotal)"
  swap_kib="$(swap_kib_real)"
  zram_kib="$(swap_kib_zram)"
  ram_gib=$(( ram_kib / 1048576 ))
  swap_gib=$(( swap_kib / 1048576 ))
  total_gib=$(( ram_gib + swap_gib ))
  compute_jobs
  local note="RAM ${ram_gib} GiB, swap ${swap_gib} GiB"
  if [ "$zram_kib" -gt 0 ]; then
    note="$note (zram ignored, it is compressed RAM)"
  fi
  if [ "$ram_gib" -ge $((RECOMMENDED_MEM_GIB - 4)) ]; then
    record preflight.memory PASS "$note; build jobs: $JOBS (about $GIB_PER_JOB GiB per job)"
    return
  fi
  if [ "$total_gib" -ge "$RECOMMENDED_MEM_GIB" ]; then
    record preflight.memory PASS "$note; below the recommended $RECOMMENDED_MEM_GIB GiB RAM, the build will lean on swap and be slower; build jobs: $JOBS"
    return
  fi
  need=$(( RECOMMENDED_MEM_GIB - total_gib ))
  fstype="$(fs_type /)"
  local status=BLOCKED
  if [ "$ALLOW_LOW_MEMORY" = 1 ] || [ "$total_gib" -ge "$MIN_MEM_GIB" ]; then
    status=UNVERIFIED
  fi
  if [ "$ALLOW_LOW_MEMORY" = 1 ]; then
    note="$note; continuing because of --allow-low-memory, the analysis phase measured about 40 GiB and may be killed"
  elif [ "$status" = UNVERIFIED ]; then
    note="$note; below the recommended $RECOMMENDED_MEM_GIB GiB, the analysis phase measured about 40 GiB so it may fit, add swap to be safe"
  else
    note="$note; the analysis phase measured about 40 GiB, add at least ${need} GiB of swap or use --allow-low-memory"
  fi
  record preflight.memory "$status" "$note; build jobs: $JOBS"
  printf '    swap is not changed by this script. To add %s GiB yourself:\n' "$need"
  if [ "$fstype" = btrfs ]; then
    printf '      sudo btrfs filesystem mkswapfile --size %sG /swapfile-openwave && sudo swapon /swapfile-openwave\n' "$need"
  else
    printf '      sudo fallocate -l %sG /swapfile-openwave && sudo chmod 600 /swapfile-openwave && sudo mkswap /swapfile-openwave && sudo swapon /swapfile-openwave\n' "$need"
  fi
  printf '      remove it later with: sudo swapoff /swapfile-openwave && sudo rm /swapfile-openwave\n'
}

pf_disk() {
  local anc fstype free need root_dev anc_dev
  anc="$(existing_ancestor "$TREE")"
  fstype="$(fs_type "$anc")"
  free="$(free_gib "$anc")"
  need="${MIN_DISK_GIB:-$MIN_FREE_GIB_FRESH}"
  if [ -z "$MIN_DISK_GIB" ] && [ -d "$TREE/.repo" ]; then
    need="$MIN_FREE_GIB_RESUME"
  fi
  if [ "$free" -ge "$need" ]; then
    record preflight.disk PASS "${free} GiB free on $anc ($fstype), need ${need} GiB"
  else
    record preflight.disk BLOCKED "only ${free} GiB free on $anc ($fstype), need ${need} GiB; use --tree on a bigger disk, or --min-disk-gb when resuming"
  fi
  case "$fstype" in
    tmpfs|ramfs) record preflight.filesystem BLOCKED "$anc is $fstype (memory); the tree needs a real disk" ;;
    overlayfs|overlay) record preflight.filesystem BLOCKED "$anc is on the container/overlay layer; mount a real volume with ${need}+ GiB and point --tree at it" ;;
    msdos|vfat|exfat|ntfs|fuseblk) record preflight.filesystem BLOCKED "$anc is $fstype; Android needs a Linux filesystem (case, symlinks, permissions)" ;;
    nfs|cifs|smb2|9p|fuse|fuse.*) record preflight.filesystem UNVERIFIED "$anc is $fstype; network and fuse filesystems are slow and untested for this build" ;;
    *) record preflight.filesystem PASS "$anc is $fstype" ;;
  esac
  if [ -n "$CONTAINER" ]; then
    root_dev="$(stat -c %d / 2>/dev/null)"
    anc_dev="$(stat -c %d "$anc" 2>/dev/null)"
    if [ -n "$root_dev" ] && [ "$root_dev" = "$anc_dev" ]; then
      record preflight.volume BLOCKED "in a container, $anc is on the same device as / ; bind-mount a host directory with ${need}+ GiB there (add :Z when SELinux is enforcing)"
    else
      record preflight.volume PASS "$anc is a separate mount from the container root"
    fi
  fi
}

pf_tree_probe() {
  local anc probe rc=0 detail=""
  anc="$(existing_ancestor "$TREE")"
  if [ "$DRY_RUN" = 1 ]; then
    record preflight.tree-probe UNVERIFIED "dry run: would test write, symlink, case-sensitivity and exec in $anc"
    return
  fi
  probe="$(mktemp -d "$anc/.openwave-probe.XXXXXX" 2>/dev/null)" || {
    record preflight.tree-probe BLOCKED "cannot write in $anc (permissions, read-only mount, or a missing :Z label for SELinux)"
    return
  }
  touch "$probe/a" "$probe/A" 2>/dev/null
  [ "$(find "$probe" -maxdepth 1 -type f | wc -l)" -eq 2 ] || { rc=1; detail="$detail case-insensitive;"; }
  ln -s a "$probe/link" 2>/dev/null && [ -L "$probe/link" ] || { rc=1; detail="$detail no-symlinks;"; }
  printf '#!/bin/sh\nexit 0\n' >"$probe/x.sh"
  chmod +x "$probe/x.sh"
  "$probe/x.sh" 2>/dev/null || { rc=1; detail="$detail not-executable (noexec mount or SELinux label);"; }
  rm -rf "$probe"
  if [ "$rc" = 0 ]; then
    record preflight.tree-probe PASS "$anc is writable, case-sensitive, supports symlinks and executables"
  else
    record preflight.tree-probe BLOCKED "$anc:$detail"
  fi
}

pf_ulimit() {
  local n
  n="$(ulimit -n)"
  if [ "$n" = unlimited ] || [ "$n" -ge 8192 ]; then
    record preflight.ulimit PASS "open files limit $n"
  else
    record preflight.ulimit BLOCKED "open files limit is $n, need 8192 or more; run 'ulimit -n 65535' in this shell first (this script does not raise it silently)"
  fi
}

pf_userns() {
  local restrict max
  restrict="$(cat /proc/sys/kernel/apparmor_restrict_unprivileged_userns 2>/dev/null)"
  max="$(cat /proc/sys/user/max_user_namespaces 2>/dev/null)"
  if [ -n "$max" ] && [ "$max" = 0 ]; then
    record preflight.userns BLOCKED "user namespaces are disabled (user.max_user_namespaces=0); the Android build sandbox needs them"
  elif [ "$restrict" = 1 ]; then
    record preflight.userns UNVERIFIED "AppArmor restricts unprivileged user namespaces; if the build fails in nsjail, run 'sudo sysctl kernel.apparmor_restrict_unprivileged_userns=0' yourself (not changed by this script)"
  else
    record preflight.userns PASS "unprivileged user namespaces available"
  fi
}

pf_packages() {
  local installer missing=() list_file="$RUN_DIR/missing-packages.txt"
  case "$OS_FAMILY" in
    debian) installer="$SCRIPT_DIR/installdep-debian.sh" ;;
    fedora) installer="$SCRIPT_DIR/installdep-fedora.sh" ;;
    *)
      record preflight.packages UNVERIFIED "no package list for $OS_PRETTY; install the LineageOS wiki build dependencies by hand"
      return
      ;;
  esac
  source "$installer"
  mapfile -t missing < <(openwave_missing_packages)
  if [ "${#missing[@]}" -eq 0 ]; then
    record preflight.packages PASS "all ${OS_FAMILY} packages present"
    return
  fi
  printf '%s\n' "${missing[@]}" >"$list_file"
  record preflight.packages BLOCKED "${#missing[@]} packages missing$( [ "$OS_FAMILY" = fedora ] && printf ' (Fedora names UNVERIFIED, mapped from the Ubuntu list)'); run scripts/$(basename "$installer")" "$list_file"
  printf '    or install them yourself with:\n      %s' "$(openwave_install_command "${missing[@]}")"
  if [ "$INSTALL_DEPS" = 1 ]; then
    if [ "$DRY_RUN" = 1 ]; then
      record preflight.install UNVERIFIED "dry run: would run $(basename "$installer"), which asks before using sudo"
    elif "$installer"; then
      record preflight.install PASS "$(basename "$installer") finished; run preflight again to confirm"
    else
      record preflight.install BLOCKED "$(basename "$installer") did not install everything (declined, no terminal, or failed)"
    fi
  fi
}

pf_fedora_extras() {
  [ "$OS_FAMILY" = fedora ] || return 0
  if ldconfig -p 2>/dev/null | grep -q 'libtinfo.so.5'; then
    record preflight.ncurses-legacy PASS "libtinfo.so.5 present (ncurses-compat-libs)"
  else
    record preflight.ncurses-legacy BLOCKED "libtinfo.so.5 missing: install ncurses-compat-libs (UNVERIFIED that it is still needed on your Fedora version)"
  fi
}

pf_python() {
  if python3 -c 'import sys; sys.exit(0 if sys.version_info >= (3, 8) else 1)' 2>/dev/null; then
    record preflight.python PASS "$(python3 --version 2>&1)"
  else
    record preflight.python BLOCKED "python3 3.8 or newer is required"
  fi
}

pf_repo() {
  if command -v repo >/dev/null 2>&1; then
    record preflight.repo PASS "repo found at $(command -v repo)"
  else
    record preflight.repo BLOCKED "repo not found; install it yourself: mkdir -p ~/bin && curl -fsSL https://storage.googleapis.com/git-repo-downloads/repo -o ~/bin/repo && chmod +x ~/bin/repo && export PATH=~/bin:\$PATH"
  fi
}

pf_git() {
  local name email
  name="$(git config --get user.name 2>/dev/null)"
  email="$(git config --get user.email 2>/dev/null)"
  if [ -z "$name" ] || [ -z "$email" ]; then
    record preflight.git-identity BLOCKED "git user.name / user.email not set; repo would prompt for them: git config --global user.name 'Your Name'; git config --global user.email you@example.com"
  else
    record preflight.git-identity PASS "git identity is configured"
  fi
  if git lfs version >/dev/null 2>&1; then
    record preflight.git-lfs PASS "$(git lfs version 2>&1 | head -n 1)"
  else
    record preflight.git-lfs BLOCKED "git-lfs not available (repo init --git-lfs needs it)"
  fi
}

pf_network() {
  if [ "$DRY_RUN" = 1 ]; then
    record preflight.network UNVERIFIED "dry run: would contact github.com and android.googlesource.com"
    return
  fi
  local failed=""
  timeout 40 git ls-remote https://github.com/LineageOS/android_build HEAD >/dev/null 2>&1 || failed="$failed github.com"
  timeout 40 git ls-remote https://android.googlesource.com/platform/build/blueprint HEAD >/dev/null 2>&1 || failed="$failed android.googlesource.com"
  if [ -z "$failed" ]; then
    record preflight.network PASS "github.com and android.googlesource.com reachable"
  else
    record preflight.network BLOCKED "cannot reach:$failed"
  fi
}

step_preflight() {
  printf '== preflight ==\n'
  local info
  pf_arch
  pf_os
  info="$(host_info)"
  record preflight.host-info PASS "host details saved" "$info"
  pf_container
  pf_glibc
  pf_compiler
  pf_cpu
  pf_memory
  pf_disk
  pf_tree_probe
  pf_ulimit
  pf_userns
  pf_packages
  pf_fedora_extras
  pf_python
  pf_repo
  pf_git
  pf_network
}

tree_shell() {
  (
    cd "$TREE" || exit 97
    unset OUT_DIR OUT_DIR_COMMON_BASE
    export LC_ALL=C TZ=UTC SOONG_NINJA=ninja
    export BUILD_NUMBER="$BUILD_NUMBER_FIXED" BUILD_DATETIME="$BUILD_DATETIME_FIXED"
    export BUILD_USERNAME="$BUILD_USERNAME_FIXED" BUILD_HOSTNAME="$BUILD_HOSTNAME_FIXED"
    export OPENWAVE_BUILD_DATE="$BUILD_DATE_FIXED"
    set +u
    source build/envsetup.sh >/dev/null || exit 98
    lunch "$LUNCH_TARGET" || exit 99
    "$@"
  )
}

in_tree() {
  ( cd "$TREE" && "$@" )
}

repo_init() {
  (
    cd "$TREE" || exit 97
    export GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=color.ui GIT_CONFIG_VALUE_0=false
    repo init "$@" </dev/null
  )
}

repo_sync_retry() {
  local attempt rc=1
  for attempt in 1 2 3; do
    printf 'repo sync attempt %s of 3\n' "$attempt"
    (
      cd "$TREE" || exit 97
      export GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=color.ui GIT_CONFIG_VALUE_0=false
      repo sync -c -j"$SYNC_JOBS" --no-tags --no-clone-bundle --optimized-fetch --retry-fetches=3 </dev/null
    )
    rc=$?
    [ "$rc" = 0 ] && return 0
    sleep $((attempt * 20))
  done
  return "$rc"
}

make_manifest_repo() {
  local dir="$WORK_DIR/manifest-repo" changed=0
  if [ "$DRY_RUN" = 1 ]; then
    printf 'DRY-RUN %-18s %s\n' sync.manifest-repo "git init $dir; copy manifests/default.xml; commit with a fixed identity and date"
    return 0
  fi
  mkdir -p "$dir" || return 1
  [ -d "$dir/.git" ] || git -C "$dir" init -q -b openwave || return 1
  if ! cmp -s "$KIT_ROOT/manifests/default.xml" "$dir/default.xml"; then
    cp "$KIT_ROOT/manifests/default.xml" "$dir/default.xml" || return 1
    changed=1
  fi
  if [ "$changed" = 1 ] || ! git -C "$dir" rev-parse -q --verify HEAD >/dev/null; then
    git -C "$dir" add default.xml || return 1
    GIT_AUTHOR_DATE="$BUILD_DATETIME_FIXED +0000" GIT_COMMITTER_DATE="$BUILD_DATETIME_FIXED +0000" \
      git -C "$dir" -c user.name="OpenWave Build" -c user.email="build@openwave.invalid" \
      commit -q -m "OpenWave pinned manifest" || return 1
  fi
  return 0
}

prepare_tree() {
  local step="$1" src="$KIT_ROOT/android/device/openwave" apk="$KIT_ROOT/android/TINH.apk"
  local dst="$TREE/device/openwave" rc
  if [ ! -f "$apk" ]; then
    record "$step.device" BLOCKED "TINH.apk not found at android/TINH.apk"
    return 1
  fi
  run_logged "$step-device" "rsync -a $src/ $dst/ ; copy TINH.apk ; regenerate the Settings overlay" \
    bash -c 'mkdir -p "$1/waydroid/tinh" && rsync -a --delete "$2/" "$1/" && install -m 0644 "$3" "$1/waydroid/tinh/TINH.apk" && python3 -I "$1/waydroid/tools/gen_settings_overlay.py"' _ "$dst" "$src" "$apk"
  rc=$?
  finish "$step.device" "$rc" "device/openwave installed with TINH.apk" "could not install device/openwave" || return 1
  if [ "$DRY_RUN" != 1 ]; then
    if diff -rq "$src/waydroid/overlay" "$dst/waydroid/overlay" >"$RUN_DIR/overlay-diff.txt" 2>&1; then
      record "$step.overlay" PASS "regenerated Settings overlay identical to the checked-in one" "$RUN_DIR/overlay-diff.txt"
    else
      record "$step.overlay" UNVERIFIED "regenerated Settings overlay differs from the checked-in one; the build uses the regenerated copy" "$RUN_DIR/overlay-diff.txt"
    fi
  fi
  run_logged "$step-patches" "python3 android/tools/apply_patches.py apply --tree $TREE" \
    python3 -I "$KIT_ROOT/android/tools/apply_patches.py" apply --tree "$TREE"
  rc=$?
  finish "$step.patches" "$rc" "Waydroid and OpenWave patch set applied" "patch set did not apply cleanly" || return 1
  run_logged "$step-patches-check" "python3 android/tools/apply_patches.py check --tree $TREE" \
    python3 -I "$KIT_ROOT/android/tools/apply_patches.py" check --tree "$TREE"
  rc=$?
  finish "$step.patches-check" "$rc" "every patch present, none pending" "patch check found pending or failed patches"
}

verify_sources() {
  local step="$1" rc
  run_logged "$step-verify" "python3 android/tools/verify_sync.py --tree $TREE --default manifests/default.xml --local manifests/local_manifests/openwave.xml --allow-ahead" \
    python3 -I "$KIT_ROOT/android/tools/verify_sync.py" --tree "$TREE" --default "$KIT_ROOT/manifests/default.xml" \
      --local "$KIT_ROOT/manifests/local_manifests/openwave.xml" --allow-ahead
  rc=$?
  finish "$step.verify" "$rc" "every project is at its pinned commit (or ahead by an OpenWave patch)" "a project is missing or not at its pinned commit"
}

step_sync() {
  printf '== sync ==\n'
  if ! command -v repo >/dev/null 2>&1; then
    record sync.repo BLOCKED "repo not found; see preflight.repo"
    return
  fi
  local anc free need
  anc="$(existing_ancestor "$TREE")"
  free="$(free_gib "$anc")"
  need="${MIN_DISK_GIB:-$MIN_FREE_GIB_FRESH}"
  [ -z "$MIN_DISK_GIB" ] && [ -d "$TREE/.repo" ] && need="$MIN_FREE_GIB_RESUME"
  if [ "$free" -lt "$need" ]; then
    record sync.disk BLOCKED "only ${free} GiB free on $anc, need ${need} GiB"
    [ "$DRY_RUN" = 1 ] || return
  fi
  local rc stale
  make_manifest_repo
  rc=$?
  if [ "$DRY_RUN" = 1 ]; then
    record sync.manifest-repo UNVERIFIED "dry run, not executed: pinned manifest repository" -
  elif [ "$rc" = 0 ]; then
    record sync.manifest-repo PASS "manifest repository at $WORK_DIR/manifest-repo, manifest hash $(manifest_hash | cut -c1-16)" -
  else
    record sync.manifest-repo FAIL "could not create the manifest repository" -
    return
  fi
  [ "$DRY_RUN" = 1 ] || mkdir -p "$TREE"
  local depth_arg=()
  [ "$DEPTH" != 0 ] && depth_arg=(--depth="$DEPTH")
  run_logged sync-init "repo init -u file://$WORK_DIR/manifest-repo -b openwave -m default.xml ${depth_arg[*]} --git-lfs --no-clone-bundle (in $TREE)" \
    repo_init -u "file://$WORK_DIR/manifest-repo" -b openwave -m default.xml "${depth_arg[@]}" --git-lfs --no-clone-bundle
  rc=$?
  finish sync.init "$rc" "repo initialised on the pinned manifest" "repo init failed" || return
  if [ "$DRY_RUN" = 1 ]; then
    printf 'DRY-RUN %-18s %s\n' sync.local-manifest "install manifests/local_manifests/openwave.xml into $TREE/.repo/local_manifests/"
    record sync.local-manifest UNVERIFIED "dry run, not executed: local manifest install" -
  else
    mkdir -p "$TREE/.repo/local_manifests"
    stale="$(find "$TREE/.repo/local_manifests" -maxdepth 1 -name '*.xml' ! -name openwave.xml 2>/dev/null)"
    if [ -n "$stale" ]; then
      record sync.local-manifest BLOCKED "other local manifests in $TREE/.repo/local_manifests would change the source set: $(printf '%s' "$stale" | tr '\n' ' '); use an empty --tree" -
      return
    fi
    cp "$KIT_ROOT/manifests/local_manifests/openwave.xml" "$TREE/.repo/local_manifests/openwave.xml" && \
      record sync.local-manifest PASS "local manifest installed" "$TREE/.repo/local_manifests/openwave.xml" || {
      record sync.local-manifest FAIL "could not install the local manifest" -
      return
    }
  fi
  LAST_LOG="$RUN_DIR/sync-fetch.log"
  run_logged sync-fetch "repo sync -c -j$SYNC_JOBS --no-tags --no-clone-bundle --optimized-fetch --retry-fetches=3 (up to 3 attempts, resumes where it stopped)" \
    repo_sync_retry
  rc=$?
  finish sync.fetch "$rc" "all projects fetched" "repo sync did not finish; run the same command again to resume" || return
  verify_sources sync || return
  prepare_tree sync
}

check_image() {
  local file="$1" kind="$2" magic
  [ -f "$file" ] || { printf 'missing'; return 1; }
  magic="$(od -An -tx1 -N4 "$file" | tr -d ' \n')"
  if [ "$magic" = 3aff26ed ]; then
    printf 'sparse image, expected a raw %s image' "$kind"
    return 1
  fi
  case "$kind" in
    erofs)
      magic="$(od -An -tx1 -j1024 -N4 "$file" | tr -d ' \n')"
      [ "$magic" = e2e1f5e0 ] || { printf 'not EROFS (magic %s)' "$magic"; return 1; }
      ;;
    ext4)
      magic="$(od -An -tx1 -j1080 -N2 "$file" | tr -d ' \n')"
      [ "$magic" = 53ef ] || { printf 'not ext4 (magic %s)' "$magic"; return 1; }
      ;;
  esac
  printf '%s, %s MiB' "$kind" $(( $(stat -c %s "$file") / 1048576 ))
}

product_out() {
  printf '%s\n' "${OPENWAVE_PRODUCT_OUT:-$TREE/out/target/product/$DEVICE}"
}

step_build() {
  printf '== build ==\n'
  compute_jobs
  local rc out
  if [ ! -f "$TREE/build/envsetup.sh" ]; then
    if [ "$DRY_RUN" = 1 ]; then
      record build.tree UNVERIFIED "dry run: no synced tree at $TREE yet, the commands below show what build would do" -
    else
      record build.tree BLOCKED "no synced tree at $TREE; run: $(basename "$SELF") sync" -
      return
    fi
  fi
  if [ "$DRY_RUN" != 1 ]; then
    local free
    free="$(free_gib "$TREE")"
    if [ "$free" -lt "${MIN_DISK_GIB:-$MIN_FREE_GIB_BUILD}" ]; then
      record build.disk BLOCKED "only ${free} GiB free on $TREE, the build needs about ${MIN_DISK_GIB:-$MIN_FREE_GIB_BUILD} GiB more" -
      return
    fi
    verify_sources build || return
  else
    printf 'DRY-RUN %-18s %s\n' build-verify "python3 android/tools/verify_sync.py --tree $TREE ..."
    record build.verify UNVERIFIED "dry run, not executed: pinned-commit check" -
  fi
  prepare_tree build || return
  smoke_prebuilts || return
  run_logged build-zipalign "cd $TREE && source build/envsetup.sh && lunch $LUNCH_TARGET && m -j$JOBS zipalign   (fail-fast: runs the full analysis and one small host module)" \
    tree_shell m -j"$JOBS" zipalign
  rc=$?
  finish build.fail-fast "$rc" "analysis finished and a small host module (zipalign) built" "the early build failed; read the log before spending hours on the full build" || return
  if [ "$DRY_RUN" != 1 ] && [ ! -x "$TREE/out/host/linux-x86/bin/zipalign" ]; then
    record build.fail-fast FAIL "m reported success but out/host/linux-x86/bin/zipalign is missing" -
    return
  fi
  run_logged build-images "cd $TREE && lunch $LUNCH_TARGET && m -j$JOBS systemimage vendorimage   (SOONG_NINJA=ninja BUILD_NUMBER=$BUILD_NUMBER_FIXED BUILD_DATETIME=$BUILD_DATETIME_FIXED OPENWAVE_BUILD_DATE=$BUILD_DATE_FIXED)" \
    tree_shell m -j"$JOBS" systemimage vendorimage
  rc=$?
  finish build.images "$rc" "m systemimage vendorimage finished" "the image build failed; resume with the same command, ninja continues" || return
  [ "$DRY_RUN" = 1 ] && return
  out="$(product_out)"
  local detail
  detail="$(check_image "$out/system.img" erofs)" && \
    record build.system-image PASS "system.img: $detail" "$out/system.img" || \
    record build.system-image FAIL "system.img: $detail" "$out/system.img"
  detail="$(check_image "$out/vendor.img" ext4)" && \
    record build.vendor-image PASS "vendor.img: $detail" "$out/vendor.img" || \
    record build.vendor-image FAIL "vendor.img: $detail" "$out/vendor.img"
}

smoke_prebuilts() {
  local bad="" ok=0 tried=0 clang jdk log="$RUN_DIR/host-prebuilts.log"
  if [ "$DRY_RUN" = 1 ] && [ ! -d "$TREE/prebuilts" ]; then
    printf 'DRY-RUN %-18s %s\n' build-smoke "run prebuilts ninja, go, clang and java with --version to prove this CPU and glibc can run them"
    record build.host-prebuilts UNVERIFIED "dry run, not executed: smoke test of the downloaded host tools" -
    return 0
  fi
  clang="$(ls -d "$TREE"/prebuilts/clang/host/linux-x86/clang-r*/bin/clang 2>/dev/null | sort -V | tail -n 1)"
  jdk="$TREE/prebuilts/jdk/jdk21/linux-x86/bin/java"
  : >"$log"
  probe_tool "$TREE/prebuilts/build-tools/linux-x86/bin/ninja" --version
  probe_tool "$TREE/prebuilts/go/linux-x86/bin/go" version
  probe_tool "${clang:-/nonexistent}" --version
  probe_tool "$jdk" -version
  if [ "$tried" -eq 0 ]; then
    record build.host-prebuilts FAIL "no prebuilt host tool found under $TREE/prebuilts; the sync is incomplete" "$log"
    return 1
  fi
  if [ -n "$bad" ]; then
    record build.host-prebuilts FAIL "prebuilt tools that could not run on this machine:$bad" "$log"
    return 1
  fi
  record build.host-prebuilts PASS "$ok of $tried prebuilt host tools ran (ninja, go, clang, java)" "$log"
}

probe_tool() {
  local bin="$1"
  shift
  [ -x "$bin" ] || return 0
  tried=$((tried + 1))
  if "$bin" "$@" >>"$log" 2>&1; then
    ok=$((ok + 1))
  else
    bad="$bad $(basename "$bin")"
  fi
}

step_package() {
  printf '== package ==\n'
  local out name dest tmp sys_detail ven_detail rc
  out="$(product_out)"
  name="openwave-android-$DEVICE-$(manifest_hash | cut -c1-8)"
  dest="$DIST_DIR/$name"
  if [ "$DRY_RUN" = 1 ]; then
    printf 'DRY-RUN %-18s %s\n' package "check $out/system.img (EROFS) and vendor.img (ext4), copy to $dest, write SHA256SUMS and build-info.txt, verify the copy"
    record package.images UNVERIFIED "dry run, not executed: image type checks and copy to $dest" -
    return
  fi
  sys_detail="$(check_image "$out/system.img" erofs)" || {
    record package.inputs BLOCKED "system.img: $sys_detail (build first)" "$out/system.img"
    return
  }
  ven_detail="$(check_image "$out/vendor.img" ext4)" || {
    record package.inputs BLOCKED "vendor.img: $ven_detail (build first)" "$out/vendor.img"
    return
  }
  record package.inputs PASS "system.img $sys_detail; vendor.img $ven_detail" "$out"
  mkdir -p "$DIST_DIR" || { record package.dist FAIL "cannot create $DIST_DIR" -; return; }
  tmp="$(mktemp -d "$DIST_DIR/.tmp-$name.XXXXXX")" || { record package.dist FAIL "cannot create a temporary directory in $DIST_DIR" -; return; }
  cp -p "$out/system.img" "$out/vendor.img" "$tmp/" || { record package.copy FAIL "copy failed (disk full?)" -; rm -rf "$tmp"; return; }
  if cmp -s "$out/system.img" "$tmp/system.img" && cmp -s "$out/vendor.img" "$tmp/vendor.img"; then
    record package.copy PASS "images copied; originals untouched and byte-identical to the copies" -
  else
    record package.copy FAIL "copies differ from the originals" -
    rm -rf "$tmp"
    return
  fi
  write_build_info "$tmp/build-info.txt" "$out"
  host_info >/dev/null
  cp "$RUN_DIR/host-info.txt" "$tmp/host-info.txt" 2>/dev/null
  cat "$WORK_DIR"/runs/*/results.tsv >"$tmp/run-history.tsv" 2>/dev/null
  if command -v repo >/dev/null 2>&1 && [ -d "$TREE/.repo" ]; then
    ( cd "$TREE" && repo manifest -r -o "$tmp/source-manifest.xml" ) >/dev/null 2>&1 || rm -f "$tmp/source-manifest.xml"
  fi
  local sum_files=(system.img vendor.img build-info.txt run-history.tsv)
  [ -f "$tmp/source-manifest.xml" ] && sum_files+=(source-manifest.xml)
  ( cd "$tmp" && sha256sum "${sum_files[@]}" >SHA256SUMS )
  if ( cd "$tmp" && sha256sum -c --quiet SHA256SUMS ); then
    record package.checksums PASS "SHA256SUMS written and verified" "$dest/SHA256SUMS"
  else
    record package.checksums FAIL "checksum verification of the copy failed" -
    rm -rf "$tmp"
    return
  fi
  rm -rf "$dest"
  mv "$tmp" "$dest" && rc=0 || rc=1
  if [ "$rc" = 0 ]; then
    record package.dist PASS "ready to send back: $dest" "$dest"
    printf '\nsend back the whole folder (or at least system.img, vendor.img, SHA256SUMS, build-info.txt):\n  %s\n' "$dest"
    ls -l "$dest"
  else
    record package.dist FAIL "could not move the package into place" -
  fi
}

write_build_info() {
  local file="$1" out="$2" head dirty
  head="$(git -C "$KIT_ROOT" rev-parse --verify -q HEAD 2>/dev/null)" || head="no-commits-yet"
  dirty="$(git -C "$KIT_ROOT" status --porcelain -- . 2>/dev/null | wc -l)"
  {
    printf 'script_version=%s\n' "$SCRIPT_VERSION"
    printf 'build_date_utc=%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    printf 'target=%s\n' "$LUNCH_TARGET"
    printf 'device=%s\n' "$DEVICE"
    printf 'source_branch=%s\n' "$MANIFEST_BRANCH"
    printf 'manifest_sha256=%s\n' "$(manifest_hash)"
    printf 'default_xml_sha256=%s\n' "$(sha256sum "$KIT_ROOT/manifests/default.xml" | cut -d' ' -f1)"
    printf 'local_manifest_sha256=%s\n' "$(sha256sum "$KIT_ROOT/manifests/local_manifests/openwave.xml" | cut -d' ' -f1)"
    printf 'kit_repo_head=%s\n' "$head"
    printf 'kit_uncommitted_files=%s\n' "$dirty"
    printf 'tinh_apk_sha256=%s\n' "$(sha256sum "$KIT_ROOT/android/TINH.apk" | cut -d' ' -f1)"
    printf 'build_number=%s\n' "$BUILD_NUMBER_FIXED"
    printf 'build_datetime=%s\n' "$BUILD_DATETIME_FIXED"
    printf 'build_jobs=%s\n' "$JOBS"
    printf 'repo_clone_depth=%s\n' "$DEPTH"
    printf 'host_os=%s\n' "${OS_PRETTY:-unknown}"
    printf 'host_kernel=%s\n' "$(uname -r)"
    printf 'host_cpu=%s\n' "$(awk -F': ' '/model name/ {print $2; exit}' /proc/cpuinfo)"
    printf 'host_cpu_threads=%s\n' "$(nproc 2>/dev/null)"
    printf 'host_ram_gib=%s\n' $(( $(mem_kib MemTotal) / 1048576 ))
    printf 'host_swap_gib=%s\n' $(( $(swap_kib_real) / 1048576 ))
    printf 'host_glibc=%s\n' "$(getconf GNU_LIBC_VERSION 2>/dev/null)"
    printf 'host_gcc=%s\n' "$(gcc --version 2>/dev/null | head -n 1)"
    printf 'host_container=%s\n' "${CONTAINER:-none}"
    printf 'system_img_bytes=%s\n' "$(stat -c %s "$out/system.img")"
    printf 'vendor_img_bytes=%s\n' "$(stat -c %s "$out/vendor.img")"
  } >"$file"
}

summary() {
  printf '\n== summary (%s) ==\n' "$COMMAND"
  printf 'PASS %s   FAIL %s   BLOCKED %s   UNVERIFIED %s\n' "$COUNT_PASS" "$COUNT_FAIL" "$COUNT_BLOCKED" "$COUNT_UNVERIFIED"
  printf 'evidence: %s\n' "$RESULTS"
  if [ "$DRY_RUN" = 1 ]; then
    printf 'dry run: nothing was fetched, built or installed.\n'
  fi
  if [ "$COUNT_FAIL" -gt 0 ]; then
    return 1
  elif [ "$COUNT_BLOCKED" -gt 0 ]; then
    return 2
  fi
  return 0
}

main() {
  load_os_release
  detect_container
  case "$COMMAND" in
    preflight) step_preflight ;;
    sync) step_sync ;;
    build) step_build ;;
    package) step_package ;;
    all)
      step_preflight
      if have_problem && [ "$DRY_RUN" = 0 ]; then
        printf '\npreflight found problems; fix them and run again (nothing was fetched or built)\n'
      else
        if have_problem; then
          printf '\ndry run: preflight found problems, showing the remaining steps anyway\n'
        fi
        step_sync
        if [ "$DRY_RUN" = 1 ]; then
          step_build
          step_package
        else
          have_problem || step_build
          have_problem || step_package
        fi
      fi
      ;;
  esac
  summary
}

main
exit $?
