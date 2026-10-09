# The host's tools where GNU/Linux and macOS (BSD userland, MacPorts)
# differ, decided in one place: sourced by tools/toolchain.sh, and so by
# every script that sources it, and by tools/bootstrap.sh, bench/run.sh,
# tools/doctor.sh and the Makefile's runner. Sourcing it runs nothing
# that can fail. A function whose tool is missing names it
# on stderr and fails; none falls back to something weaker.
#
# On macOS coreutils come from MacPorts (sudo port install coreutils):
# /opt/local/bin, which may not be on a non-interactive shell's PATH, so
# the GNU spellings are looked for there too.

# host_names: the names a test's `targets` file and its expected.<name>
# files give this host (tests/Main.idr, tests/runner/one.sh): its
# architecture, x86-64 or aarch64, then its operating system, linux or
# macos. The Makefile exports them as IDRIS_MLIR_HOST_NAMES.
case $(uname -m) in
  x86_64 | amd64) host_names=x86-64 ;;
  arm64 | aarch64) host_names=aarch64 ;;
  *) host_names=$(uname -m) ;;
esac
case $(uname -s) in
  Linux) host_names="$host_names linux" ;;
  Darwin) host_names="$host_names macos" ;;
  *) host_names="$host_names $(uname -s | tr '[:upper:]' '[:lower:]')" ;;
esac

# host_path NAME...: the first of NAME that is on PATH or in MacPorts'
# bin, printing its path, or nothing.
host_path() {
  for host_path_name in "$@"; do
    if host_path_found=$(command -v "$host_path_name" 2> /dev/null); then
      printf '%s\n' "$host_path_found"
      return 0
    fi
    if [ -x "/opt/local/bin/$host_path_name" ]; then
      printf '%s\n' "/opt/local/bin/$host_path_name"
      return 0
    fi
  done
  return 1
}

# coreutils' timeout, which kills what it ran with everything that started
# (it runs it in a process group of its own): `timeout` on Linux, and on
# macOS coreutils' `gtimeout` from MacPorts. Empty when there is none;
# every caller stops then, since without it a command could hang.
timeout_cmd=$(host_path timeout gtimeout) || timeout_cmd=
timeout_missing="no timeout command (coreutils; on macOS: sudo port install coreutils, for gtimeout)"

# The nanosecond clock: GNU date's %N on Linux; macOS's date has none, so
# perl's Time::HiRes there, which ships with macOS and reads microseconds.
case $(date +%N 2> /dev/null) in
  '' | *[!0-9]*) host_clock=perl ;;
  *) host_clock=date ;;
esac

# now_ns: the wall clock in nanoseconds since the epoch.
now_ns() {
  case $host_clock in
    date) date +%s%N ;;
    perl)
      perl -MTime::HiRes=gettimeofday -e '($s, $us) = gettimeofday; printf "%d%06d000\n", $s, $us' ||
        { echo "no nanosecond clock: neither GNU date's %N nor perl's Time::HiRes" >&2; return 1; } ;;
  esac
}

# sha256 [FILE...]: each FILE's SHA-256 (stdin's without one), as
# coreutils' sha256sum prints it: coreutils' on Linux, and on macOS
# coreutils' `gsha256sum` from MacPorts (macOS ships a `sha256sum` of its
# own on recent releases; coreutils' is tried first where both exist);
# `shasum -a 256`, which prints the same, is the fallback.
sha256() {
  case $(uname -s) in
    Darwin) sha256_tool=$(host_path gsha256sum sha256sum shasum) || sha256_tool= ;;
    *) sha256_tool=$(host_path sha256sum gsha256sum shasum) || sha256_tool= ;;
  esac
  case ${sha256_tool##*/} in
    shasum) shasum -a 256 "$@" ;;
    '') echo "no sha256sum (coreutils) or shasum (perl's) to compute a SHA-256" >&2; return 1 ;;
    *) "$sha256_tool" "$@" ;;
  esac
}

# memory_kib: the machine's memory in KiB, from /proc/meminfo on Linux and
# sysctl's hw.memsize (bytes) on macOS; 0 when neither says.
memory_kib() {
  if [ -r /proc/meminfo ]; then
    awk '/^MemTotal:/ { print $2; exit }' /proc/meminfo
  elif memory_bytes=$(sysctl -n hw.memsize 2> /dev/null); then
    echo $((memory_bytes / 1024))
  else
    echo 0
  fi
}

# memory_used_kib: the memory in use on the machine, in KiB: what is not
# available (/proc/meminfo) on Linux; on macOS, vm_stat's active, wired and
# compressed pages, in the page size it states. 0 when neither says.
memory_used_kib() {
  if [ -r /proc/meminfo ]; then
    awk '/^MemTotal:/ { t = $2 } /^MemAvailable:/ { a = $2 } END { print (t > 0 ? t - a : 0) }' /proc/meminfo
  elif command -v vm_stat > /dev/null 2>&1; then
    vm_stat | awk '
      /page size of/ { for (i = 1; i <= NF; i++) if ($i == "of") size = $(i + 1) }
      /^Pages (active|wired down|occupied by compressor):/ { sub(/\./, "", $NF); pages += $NF }
      END { print (size > 0 ? int(pages * size / 1024) : 0) }'
  else
    echo 0
  fi
}

# cpu_name: the processor's name, for a benchmark table's header:
# /proc/cpuinfo's model name on Linux (or its CPU part on arm64), sysctl's
# machdep.cpu.brand_string on macOS, and hw.model where the brand string is
# absent (some Apple Silicon releases); `unknown` when neither says.
cpu_name() {
  cpu_name_text=
  if [ -r /proc/cpuinfo ]; then
    cpu_name_text=$(awk -F': *' '/^(model name|Hardware|CPU part)[[:space:]]*:/ { print $2; exit }' /proc/cpuinfo)
  else
    cpu_name_text=$(sysctl -n machdep.cpu.brand_string 2> /dev/null)
    [ -n "$cpu_name_text" ] || cpu_name_text=$(sysctl -n hw.model 2> /dev/null)
  fi
  printf '%s\n' "${cpu_name_text:-unknown}"
}

# stack_hard_max: the hard stack limit (ulimit -H -s) in KiB, or unlimited.
# macOS caps it near 64 MiB, which is why a program that recurses deeply
# must be run differently there, not with a larger limit (bench/run.sh).
stack_hard_max() {
  ulimit -H -s
}

# stack_max: raises this shell's stack limit (ulimit -s), for what it runs
# after, as far as the system allows: unlimited where the hard limit is (as
# on Linux, usually), else the hard limit (macOS caps it near 64 MiB).
stack_max() {
  ulimit -s unlimited 2> /dev/null || ulimit -s "$(ulimit -H -s)"
}

# with_lock DIR CMD...: CMD, run while holding the mutex DIR, which mkdir
# makes atomically and which holds its holder's process ID; it waits while
# another process holds it. A mutex whose holder is gone (killed before it
# could remove it) is taken over, and says so. It sets the shell's EXIT,
# HUP, INT and TERM traps, so that an interrupted CMD leaves no mutex.
with_lock() {
  with_lock_dir=$1
  shift
  with_lock_waiting=
  until mkdir "$with_lock_dir" 2> /dev/null; do
    with_lock_holder=$(cat "$with_lock_dir/pid" 2> /dev/null)
    if [ -n "$with_lock_holder" ] && ! kill -0 "$with_lock_holder" 2> /dev/null &&
      [ "$(cat "$with_lock_dir/pid" 2> /dev/null)" = "$with_lock_holder" ]; then
      echo "$with_lock_dir: its holder, process $with_lock_holder, is gone; taking it over" >&2
      rm -rf "$with_lock_dir"
      continue
    fi
    if [ -z "$with_lock_waiting" ]; then
      echo "waiting for $with_lock_dir, held by process ${with_lock_holder:-unknown} (if none holds it, remove it)" >&2
      with_lock_waiting=yes
    fi
    sleep 1
  done
  trap 'rm -rf "$with_lock_dir"' EXIT
  trap 'exit 1' HUP INT TERM
  echo $$ > "$with_lock_dir/pid"
  "$@"
  with_lock_status=$?
  rm -rf "$with_lock_dir"
  trap - EXIT HUP INT TERM
  return "$with_lock_status"
}
