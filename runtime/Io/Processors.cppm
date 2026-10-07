// rt.io:processors: the processor count System.Info.getNProcessors reads.
// PIN(runtime-quarantine) — see PINS.md
module;
#include "idris_rt.h"

#include <stdint.h>

export module rt.io:processors;

import rt.platform;

extern "C" int64_t idris_rt_io_n_processors(void) { return rt::platform::nprocessors(); }
