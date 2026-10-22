// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// GMP's memory functions over the runtime's allocator. GMP cannot recover
// from a failed allocation, and none returns one: rt::alloc ends the
// process as out of memory instead. GMP is built to take its temporaries
// from these too, never from the stack, so its depth is no part of a
// program's stack.
// PIN(runtime-quarantine) — see PINS.md
#include "Alloc/Alloc.h"
#include "Start/Start.h"
#include "idris_rt.h"

#include <stddef.h>

#include <gmp.h>

namespace {

void *allocate(size_t size) { return rt::alloc::allocate(size); }

void *reallocate(void *block, size_t, size_t size) { return rt::alloc::reallocate(block, size); }

void release(void *block, size_t) { rt::alloc::release(block); }

} // namespace

// The runner sets them once, after the heap and before any thread that
// may run a big operation starts: a program's and a tool's alike.
void rt::start::pointGmp() noexcept { mp_set_memory_functions(allocate, reallocate, release); }
