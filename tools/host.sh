# SPDX-License-Identifier: 0BSD
# Copyright (c) 2026 Bjorn Pagen
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
# files give this host (harness/Main.idr, harness/one.sh): its
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

# The one CPU budget every build, test and compile in this repository
# runs under: IDRIS_MLIR_NCPU when it names a positive count, else every
# CPU of the machine. The default is maximal on purpose; a caller that
# wants headroom sets the variable once (the Makefile exports its NCPU
# as it, so nested scripts agree), and each layer -- make's job count,
# the test runner's threads, bootstrap's jobs, a compilation's
# --num-threads -- reads the same number here. $ncpu is that budget;
# $ncpu_total is the machine's count.
case $(uname -s) in
  Darwin) ncpu_total=$(sysctl -n hw.ncpu 2> /dev/null) || ncpu_total= ;;
  *) ncpu_total=$(getconf _NPROCESSORS_ONLN 2> /dev/null) || ncpu_total= ;;
esac
case $ncpu_total in '' | *[!0-9]* | 0) ncpu_total=1 ;; esac
ncpu=$ncpu_total
case ${IDRIS_MLIR_NCPU:-} in
  '' | *[!0-9]* | 0) ;;
  *) ncpu=$IDRIS_MLIR_NCPU ;;
esac
if [ "$ncpu" -gt "$ncpu_total" ]; then ncpu=$ncpu_total; fi

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

# coreutils' date, whose %N is the nanoseconds: `date` on Linux, and on
# macOS coreutils' `gdate` from MacPorts (macOS's own date has no %N).
case $(uname -s) in
  Darwin) date_cmd=$(host_path gdate) || date_cmd= ;;
  *) date_cmd=$(host_path date) || date_cmd= ;;
esac

# now_ns: the wall clock in nanoseconds since the epoch.
now_ns() {
  [ -n "$date_cmd" ] || { echo "no coreutils date (on macOS: sudo port install coreutils, for gdate)" >&2; return 1; }
  "$date_cmd" +%s%N
}

# sha256 [FILE...]: each FILE's SHA-256 (stdin's without one): coreutils'
# sha256sum on Linux, and on macOS coreutils' `gsha256sum` from MacPorts
# (not the `sha256sum` macOS ships on recent releases, which is another
# tool).
case $(uname -s) in
  Darwin) sha256_tool=$(host_path gsha256sum) || sha256_tool= ;;
  *) sha256_tool=$(host_path sha256sum) || sha256_tool= ;;
esac
sha256() {
  [ -n "$sha256_tool" ] || { echo "no sha256sum (coreutils; on macOS: sudo port install coreutils, for gsha256sum)" >&2; return 1; }
  "$sha256_tool" "$@"
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

# The unit getrusage counts a process's peak resident set size in: bytes
# on macOS, KiB on Linux.
case $(uname -s) in
  Darwin) peak_rss_unit=1024 ;;
  *) peak_rss_unit=1 ;;
esac

# peak_memory FILE CMD...: runs CMD, whose output and exit status are its
# own (128 plus the signal that killed it), and writes to FILE the most
# memory it, or a process it waited for, held resident at once, in KiB, on
# one line: the getrusage that wait4 returns with its status. Through
# python3, which the host provides for the bootstrap: a host may have no
# /usr/bin/time, and where it has one, its options and units differ.
peak_memory() {
  peak_memory_file=$1
  shift
  python3 -I -c '
import os, signal, sys
path, unit, argv = sys.argv[1], int(sys.argv[2]), sys.argv[3:]
pid = os.fork()
if pid == 0:
    try:
        os.execvp(argv[0], argv)
    except OSError as error:
        print(f"{argv[0]}: {error.strerror}", file=sys.stderr)
    os._exit(127)
# An interrupt, a termination or a hangup goes on to CMD, whose own
# handling decides when it ends: timeout(1) puts itself in a process group
# of its own, so a terminal signal would not reach it otherwise.
for signum in (signal.SIGINT, signal.SIGTERM, signal.SIGHUP):
    signal.signal(signum, lambda signum, frame: os.kill(pid, signum))
_, status, usage = os.wait4(pid, 0)
with open(path, "w") as out:
    print(usage.ru_maxrss // unit, file=out)
sys.exit(128 + os.WTERMSIG(status) if os.WIFSIGNALED(status) else os.WEXITSTATUS(status))
' "$peak_memory_file" "$peak_rss_unit" "$@"
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
