// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// An id, and the count of a set of ids, are made only by the set's minter:
// an id in hand names something its owner numbered, and only the owner
// says how long an array of its facts is. Anyone else's is refused.

#include "idr/Support/Id.h"

#include <cstdint>

struct Things {
  struct Minter;
};
using Thing = idr::Id<Things>;

// The minter may.
struct Things::Minter {
  static Thing first() { return Thing(0); }
  static idr::Count<Thing> count(std::uint32_t n) { return idr::Count<Thing>(n); }
};

Thing forgedId() {
  return Thing(3); // expected-error {{calling a private constructor of class 'idr::Id}}
}

idr::Count<Thing> forgedCount() {
  return idr::Count<Thing>(3); // expected-error {{calling a private constructor of class 'idr::Count}}
}
