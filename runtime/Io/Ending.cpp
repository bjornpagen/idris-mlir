// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// How a program ends: returning from main, base's exit, or a crash.
// PIN(runtime-quarantine) — see PINS.md
#include "Io/Io.h"
#include "Platform/Platform.h"
#include "Start/Start.h"
#include "Strings/Strings.h"
#include "idris_rt.h"

#include <stddef.h>
#include <stdint.h>
#include <string.h>

namespace {

// The live cells on standard error when IDRIS_RT_LIVE is "1", in one write:
// how a test sees that a program frees every cell it allocates.
void reportLiveCells() {
  const char *setting = rt::platform::environment("IDRIS_RT_LIVE");
  if (setting == nullptr || setting[0] != '1' || setting[1] != '\0')
    return;
  static constexpr char prefix[] = "idris-rt: live cells ";
  constexpr size_t prefixLength = sizeof prefix - 1;
  char line[prefixLength + rt::strings::intTextMax + 1];
  char *end = line + sizeof line;
  end[-1] = '\n';
  char *start = rt::strings::formatUnsigned(idris_rt_live_cells(), end - 1) - prefixLength;
  memcpy(start, prefix, prefixLength);
  rt::platform::writeAll(2, start, static_cast<size_t>(end - start));
}

} // namespace

// What @main calls right before it returns: writes pending output and
// releases the handle table (its files, directories, and the strings the
// runtime holds for environment and directory handles, which are then not
// counted as live), then, when the environment variable IDRIS_RT_LIVE is
// exactly "1", writes the line "idris-rt: live cells N\n" (N in decimal,
// idris_rt_live_cells) to standard error, so a test can check that a program
// frees every cell it allocates. A crash reports nothing, and neither does
// idris_rt_io_exit. The handle table goes before the count: the strings the
// runtime keeps for the environment and for directories are its own, not
// cells the program left live.
extern "C" void idris_rt_main_return(void) {
  idris_rt_flush();
  rt::io::releaseHandles();
  reportLiveCells();
}

// Base's exit: what main's return writes, standard output's buffer and every
// open file's, and then the end with the status, with no count: a program
// that exits with cells still live has not leaked them. A status no parent
// could read is then a crash that names it, as main's return is, after the
// same output.
extern "C" void idris_rt_io_exit(int64_t status) {
  idris_rt_flush();
  rt::io::releaseHandles();
  rt::start::checkStatus(status, rt::start::Ending::exited);
  rt::platform::exitProcess(static_cast<int>(status));
}

// Lowered code crashes through this one entry: it writes pending output,
// then the crash's message, `idris-mlir: `, the `len` bytes of `cause` and a
// newline, to standard error, and ends the process with IDRIS_RT_CRASHED.
extern "C" void idris_rt_crash(const char *cause, size_t len) {
  idris_rt_flush();
  rt::platform::Piece piece{cause, len};
  rt::platform::writeCrash(&piece, 1);
  rt::platform::exitProcess(IDRIS_RT_CRASHED);
}

// A crash whose cause is the string's bytes.
extern "C" void idris_rt_crash_str(const idris_rt_str *s) {
  idris_rt_crash(idris_rt_str_bytes(s), s->bytes);
}
