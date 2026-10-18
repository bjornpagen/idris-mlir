// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The simdutf implementation every string function calls, and the C ABI's
// scalar count over it.
// PIN(runtime-quarantine), PIN(simdutf-dispatch) — see PINS.md
#include "Platform/Platform.h"
#include "Strings/Strings.h"
#include "idris_rt.h"

#include <stddef.h>

#include <atomic>

#include <simdutf.h>

namespace {

// The implementation every string function calls, chosen once. The pointer
// starts null with no constructor, and racing threads store the same value.
std::atomic<const simdutf::implementation *> selected{nullptr};

// simdutf's own dispatch reads SIMDUTF_FORCE_IMPLEMENTATION, so a program's
// results would depend on its environment, and detects the processor itself
// (cpuid in inline assembly, with one feature bit shared by two features).
// The runtime asks neither: it takes the best implementation of simdutf's
// list, which is in priority order, that the target's processor test says
// runs. Reading the list and the names runs no detection. The list ends with
// the one the runtime's own baseline runs (the fallback, or the kernel the
// baseline already enables), which is the choice when the test accepts none.
const simdutf::implementation *choose() {
  const simdutf::internal::available_implementation_list &list =
      simdutf::get_available_implementations();
  for (const simdutf::implementation *candidate : list)
    if (rt::platform::runsSimdutf(candidate->name()))
      return candidate;
  return list.end()[-1];
}

} // namespace

namespace rt::strings {

const simdutf::implementation &implementation() {
  const simdutf::implementation *chosen = selected.load(std::memory_order_relaxed);
  if (chosen == nullptr) [[unlikely]] {
    chosen = choose();
    selected.store(chosen, std::memory_order_relaxed);
  }
  return *chosen;
}

} // namespace rt::strings

// The number of scalar values in n bytes of well-formed UTF-8, over
// simdutf: what a string's scalar count is, for a string idr-lower writes
// into static data.
extern "C" size_t idris_rt_utf8_count(const char *p, size_t n) {
  return rt::strings::implementation().count_utf8(p, n);
}
