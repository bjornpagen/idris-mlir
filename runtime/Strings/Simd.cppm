// rt.strings:simd: the simdutf implementation every string function calls,
// and the C ABI's count and check over it.
// PIN(runtime-quarantine), PIN(simdutf-dispatch) — see PINS.md
module;
#include "idris_rt.h"

#include <atomic>

#include <simdutf.h>

export module rt.strings:simd;

namespace {

// simdutf's own dispatch reads SIMDUTF_FORCE_IMPLEMENTATION on first use, and
// a value that names no implementation makes every later call fail, so a
// program's results would depend on its environment. The runtime picks the
// best implementation the CPU supports itself. The pointer starts null with
// no constructor, and racing threads store the same value.
std::atomic<const simdutf::implementation *> selected{nullptr};

} // namespace

namespace rt::strings {

const simdutf::implementation &implementation() {
  const simdutf::implementation *chosen = selected.load(std::memory_order_relaxed);
  if (chosen == nullptr) [[unlikely]] {
    chosen = simdutf::get_available_implementations().detect_best_supported();
    selected.store(chosen, std::memory_order_relaxed);
  }
  return *chosen;
}

} // namespace rt::strings

extern "C" size_t idris_rt_utf8_count(const char *p, size_t n) {
  return rt::strings::implementation().count_utf8(p, n);
}

extern "C" bool idris_rt_ascii(const char *p, size_t n) {
  return rt::strings::implementation().validate_ascii(p, n);
}
