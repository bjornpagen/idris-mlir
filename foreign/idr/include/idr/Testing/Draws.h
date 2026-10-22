// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The draws of a box that builds its cases from seeds: the same seed gives
// the same case on every target, so a failure names its seed and is read
// again from it. The generator is SplitMix64, written here, since each
// standard library's distributions are its own. A case's own weights are
// drawn first from its seed, so one case leans hard on one choice and the
// next on another.
#ifndef IDR_TESTING_DRAWS_H
#define IDR_TESTING_DRAWS_H

#include "idr/Support/Enum.h"

#include "llvm/ADT/STLExtras.h"

#include <cstddef>
#include <cstdint>

namespace idr::box {

class Draws {
public:
  explicit Draws(std::uint64_t seed) : state(seed) {}

  // A number below `bound`, which is above zero.
  unsigned below(std::size_t bound) { return static_cast<unsigned>(next() % bound); }

  // A case drawn by the weights of the cases, whose first case weighs at
  // least one, so a draw is never from nothing: each choice keeps one way
  // that is always open first, and a weight that closes a way is zero.
  template <Enumerated E>
  E weighted(const EnumArray<E, unsigned> &weights) {
    constexpr auto cases = allOf<E>();
    unsigned total = 0;
    for (E e : cases)
      total += weights[e];
    unsigned at = below(total);
    for (E e : llvm::drop_end(cases)) {
      if (at < weights[e])
        return e;
      at -= weights[e];
    }
    return cases.back();
  }

private:
  std::uint64_t next() {
    std::uint64_t z = state += 0x9e3779b97f4a7c15u;
    z = (z ^ (z >> 30)) * 0xbf58476d1ce4e5b9u;
    z = (z ^ (z >> 27)) * 0x94d049bb133111ebu;
    return z ^ (z >> 31);
  }

  std::uint64_t state;
};

} // namespace idr::box

#endif // IDR_TESTING_DRAWS_H
