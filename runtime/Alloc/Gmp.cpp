// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// GMP's memory functions over the runtime's allocator. GMP cannot recover
// from a failed allocation; rt::alloc ends the process with a crash instead
// of returning. They are set once, before a program's big operations run, so
// none tests for them.
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

// Points GMP's memory functions at the runtime's allocator, so that GMP's
// scratch integers come from snmalloc and exhausted memory is the runtime's
// crash. idris_rt_start calls it before the program runs, while no other
// thread can use GMP. A process that runs big operations without
// idris_rt_start (idris-mlir, whose folders call them) may call it before
// it starts any thread that does; GMP otherwise allocates through the C
// library, which is as correct, since every integer GMP allocates is freed
// before the operation that made it returns.
extern "C" void idris_rt_gmp_init(void) { mp_set_memory_functions(allocate, reallocate, release); }
