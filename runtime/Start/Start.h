// rt::start: the program's entry and the reserved-stack runner. A program's
// main calls idris_rt_start, which checks the processor, keeps the
// program's arguments and runs the program on a reserved stack, so that
// running out of it is a named crash rather than a bare fault that loses the
// buffered output. idris-mlir runs on the same runner, with a stack of its
// own size. What it needs of the system is in the platform layer
// (rt::platform).
// PIN(runtime-quarantine) — see PINS.md
#pragma once

#include "idris_rt.h"

#include <stdint.h>

namespace rt::start {

// What ended the program with a status, which its crash names.
enum class Ending { mainReturned, exited };

// A parent sees only the low 8 bits of an exit status, so 256 would read as
// success and -1 as 255. A status outside 0 to 255 is one the process
// cannot report, whether main returned it or the program exited with it, and
// ends it as a crash that says so.
void checkStatus(int64_t status, Ending ending);

// The number of the program's arguments, which idris_rt_start kept.
int64_t argumentCount();

// A new string of argument i, whose bytes are decoded as any bytes from
// outside the program are; the empty string when there is no argument i.
const idris_rt_str *argument(int64_t i);

} // namespace rt::start
