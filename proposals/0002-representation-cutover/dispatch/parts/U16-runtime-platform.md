# U16 — Base's surface in the runtime: files, directories, clocks, environment, terminal, handles

Mandatory findings: F-base-2 F-base-7

## Permitted outcome

1. **One runtime function per op.** Every op of C9.2 and C9.3 has one
   runtime function, `idris_rt_io_<name>` or `idris_rt_handle_<name>`,
   with C1.5's signature. Its meaning is C9.2's: the C support
   function's. It works on x86_64 Linux and arm64 macOS, and every OS
   call goes through `RT/Platform/Posix`. Mandatory.
2. **The handle table.** It holds files, directories, file times and
   strings, behind the `i64` handles of C9.1: 0, 1 and 2 are the
   standard streams, -1 is null, and every other value is a slot.
   Mandatory.
3. **Existing ops on file handles.** `read_bytes`, `write_bytes` and
   `eof` serve file handles. Reads on 0 share the input buffer, and
   writes on 1 and 2 share the output path. Mandatory.
4. **`OSClock`** values are immediate, packed per C9.4. Mandatory.
5. **The argument functions.** `idr.io.arg_count` and `idr.io.arg` read
   `rt::start::argumentCount()` and `rt::start::argument(i)` (U15).
   Mandatory.

## Owner / exclusive writes

- `RT/Platform`
- `RT/Io`
- `RT/CMakeLists.txt`

**Excluded:**

- `RT/idris_rt.h`, whose declarations the coordinator writes from C1.5.
- `RT/Start`, `RT/Rc`, `RT/Eval` and `RT/Alloc` (U15).
- `INC/IdrPlatformOps.td` (the coordinator).
- `third_party/Idris2`, which is read-only; its `support/c/` files are
  the reference for meanings.

## Read first

- `contracts.md` C9 (all), C1.5 and C13.
- `findings.md` F-base-1, F-base-2 and F-base-7.
- `third_party/Idris2/support/c/idris_file.c`, `idris_directory.c`,
  `idris_support.c`, `idris_term.c` and `idris_clock.c` (or the files
  that define each `%foreign` function C9.2 names).
- `RT/Io/*` and `RT/Platform/*`, all of them.
- `RT/CMakeLists.txt`'s `rt_io` and `rt_platform` file sets.
- `RT/check-archive.sh`, for what it checks of exported symbols.

## Fixed decisions

- **The handle table** is one per process: a growable array of slots.
  - A slot holds a kind (file, dir, filetime or string) and its payload:
    a `FILE *`, a `DIR *`, six `int64_t`, or an `idris_rt_str *` with
    one reference.
  - Handles are slot index plus 3, so slot 0 is handle 3. Handle -1 is
    null.
  - Freed slots are reused.
  - `idr.io.handle_free` and `file_close` / `dir_close` free their
    slots. The string in a string slot loses its reference.
  - `idris_rt_handle_string(h)` returns the slot's string with one new
    reference.
- **The standard streams** are 0, 1 and 2.
  - `file_read_line`, `file_read_chars`, `file_read_char`, `read_bytes`
    and `eof` on 0 use `RT/Io/Input.cppm`'s buffer.
  - `file_write_line`, `write_bytes` and `file_flush` on 1 and 2 use
    `RT/Io/Output.cppm`'s path.
  - Other handles use the slot's `FILE *`.
- **errno.** Each failing call saves `errno` in the runtime.
  `idr.io.errno` and `idr.io.file_errno` return the saved value.
  `strerror` returns a new runtime string.
- **Strings** returned as a handle (`file_read_line`, `file_read_chars`,
  `dir_current`, `dir_entry`, `env_get`, `env_pair`) are new runtime
  strings placed in a string slot. At end of input or on failure the
  result is null, exactly when the C support function returns `NULL`.
- **`OSClock`** is `seconds << 30 | nanoseconds` from `clock_gettime`
  (`CLOCK_MONOTONIC`, `CLOCK_REALTIME`, `CLOCK_PROCESS_CPUTIME_ID`,
  `CLOCK_THREAD_CPUTIME_ID`). It is -1 when that fails, and -1 always
  for the two GC clocks. `clock_valid`, `clock_second` and
  `clock_nanosecond` unpack it.
- **The target-specific parts** are one function each in
  `RT/Platform/Posix/` (C9.6):
  - the `stat` time fields;
  - `TIOCGWINSZ`;
  - raw mode (`termios`);
  - the clock ids.

  `RT/Io` calls them.
- **`exit`** writes pending output, as `idris_rt_main_return` does, then
  calls `_exit(status)` through the platform layer.

## Inputs

- C1.5's declarations.
- `rt::start::argumentCount` and `rt::start::argument` (U15).
- The runtime string API (`RT/Strings`).

## Outputs

- The runtime functions of C9.2 and C9.3, in new `RT/Io` partitions, for
  example `Files.cppm`, `Directories.cppm`, `Process.cppm`, `Clock.cppm`,
  `Terminal.cppm` and `Handles.cppm`, with their `RT/Platform/Posix`
  helpers.
- `RT/CMakeLists.txt` listing them.

## Implement

- Per the fixed decisions, one partition per group, each 400 lines or
  fewer.
- Extend the existing `read_bytes`, `write_bytes` and `eof`
  implementations to file handles.

## Delete

- The "any other handle reads nothing and gives 0" branches of
  `read_bytes`, `write_bytes` and `eof`, which file handles replace.

## NOT TO DO

- Do not implement `system`, `popen` or signals (C9.5).
- Do not use a third-party library.
- Do not add a thread.
- Do not change the standard streams' buffering or the output order.
- Do not let a raw address reach a handle's value.
- Do not write Linux- or macOS-only code outside `RT/Platform/Posix`'s
  helpers.

## Acceptance

- U23's `files-roundtrip`, `directory-listing`, `environment-arguments`
  and `clock-monotonic` match Chez where C12 says so. The coordinator
  runs them.
- `fGetLine stdin` and `getLine` interleave on one input without loss.
- A program that opens and closes 10^6 files in a loop keeps a bounded
  handle table, because slots are reused.
- `make check`'s runtime checks (`check-archive.sh` and its symbol rules)
  pass. You may run `make check`.
- **Tempting partial:** returning the `FILE *` as the handle. Rejected:
  an address in Idris code is exactly what O1 excludes, and `0` would
  never be null.

## Escalate if

- A C support function's meaning depends on Chez-only behaviour that
  C9.2 does not settle. Report the function, and Chez's output against
  the C one.
- A primitive needs a platform facility macOS lacks. Report it.

## Stop and return

You are done when every C9.2 and C9.3 function exists on both targets'
code paths, and the existing transfer ops serve file handles. Return the
changed paths, the symbol list for the coordinator to check against
C1.5, `Verification: make check (run) / builds NotRun (swarm policy)`,
and seams.
