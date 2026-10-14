// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// Raw memory, which is not a cell (GMP's scratch integers, scratch
// buffers), from snmalloc.
// PIN(runtime-quarantine) — see PINS.md
#include "Alloc/Alloc.h"
#include "idris_rt.h"

#include <stddef.h>

namespace rt::alloc {

void outOfMemory() {
  static constexpr char message[] = "idris runtime: out of memory\n";
  idris_rt_crash(message, sizeof message - 1);
}

void *allocate(size_t size) {
  void *block = idris_rt_alloc(size);
  if (block == nullptr)
    outOfMemory();
  return block;
}

void release(void *block) { idris_rt_free(block); }

} // namespace rt::alloc
