// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// GMP's memory functions over the runtime's allocator. GMP cannot recover
// from a failed allocation; rt::alloc ends the process with a crash instead
// of returning. idris_rt_start sets them once, before the program runs and
// before any thread exists, so no big operation tests for them.
// PIN(runtime-quarantine) — see PINS.md
#include "Alloc/Alloc.h"
#include "idris_rt.h"

#include <stddef.h>

#include <gmp.h>

namespace {

void *allocate(size_t size) { return rt::alloc::allocate(size); }

void *reallocate(void *block, size_t, size_t size) { return rt::alloc::reallocate(block, size); }

void release(void *block, size_t) { rt::alloc::release(block); }

} // namespace

extern "C" void idris_rt_gmp_init(void) { mp_set_memory_functions(allocate, reallocate, release); }
