// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The processor count System.Info.getNProcessors reads.
#include "Platform/Platform.h"
#include "idris_rt.h"

#include <stdint.h>

// How many processors are online, read when asked; -1 when the system does
// not say, which System.Info.getNProcessors turns into Nothing.
extern "C" int64_t idris_rt_io_n_processors(void) { return rt::platform::nprocessors(); }
