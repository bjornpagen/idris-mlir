// The processor count System.Info.getNProcessors reads.
// PIN(runtime-quarantine) — see PINS.md
#include "Platform/Platform.h"
#include "idris_rt.h"

#include <stdint.h>

extern "C" int64_t idris_rt_io_n_processors(void) { return rt::platform::nprocessors(); }
