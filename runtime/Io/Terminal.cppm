// rt.io:terminal: base's terminal (System, System.Term): raw mode on
// standard input, and the size of the terminal.
// PIN(runtime-quarantine) — see PINS.md
module;
#include "idris_rt.h"

#include <stdint.h>

export module rt.io:terminal;

import rt.platform;
import :errors;

// Standard input in raw mode, without echo and without line editing, its
// mode before saved the first time: 0, or -1 when its mode cannot be read or
// set (when it is no terminal).
extern "C" int64_t idris_rt_io_term_raw(void) {
  if (rt::platform::rawMode())
    return 0;
  rt::io::saveError();
  return -1;
}

// Puts standard input back in the mode it had before raw mode; nothing when
// raw mode never ran.
extern "C" void idris_rt_io_term_reset(void) { rt::platform::restoreMode(); }

// Base's setupTerm: a POSIX terminal needs no preparing.
extern "C" void idris_rt_io_term_setup(void) {}

// The terminal's columns, from standard input's terminal or else standard
// output's; 0 when neither is one.
extern "C" int64_t idris_rt_io_term_cols(void) {
  int64_t columns = 0;
  int64_t rows = 0;
  return rt::platform::terminalSize(columns, rows) ? columns : 0;
}

// The terminal's lines, as idris_rt_io_term_cols reads its columns.
extern "C" int64_t idris_rt_io_term_lines(void) {
  int64_t columns = 0;
  int64_t rows = 0;
  return rt::platform::terminalSize(columns, rows) ? rows : 0;
}
