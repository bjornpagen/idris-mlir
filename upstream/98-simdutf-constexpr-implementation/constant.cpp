// constant.cpp: what a program built for one simdutf implementation holds,
// a constant object of that implementation's own (final) class, and a call
// through it, which is direct. At simdutf 9.3.2 the constant does not
// compile: the implementation's constructor is not constexpr.
//
//   c++ -std=c++20 -fsyntax-only -DSIMDUTF_IMPLEMENTATION_FALLBACK=1 \
//       -I <simdutf>/include -I <simdutf>/src constant.cpp
#include "simdutf/fallback/implementation.h"

#include <cstddef>

constexpr simdutf::fallback::implementation utf8{};

std::size_t count(const char *p, std::size_t n) {
  return utf8.count_utf8(p, n);
}
