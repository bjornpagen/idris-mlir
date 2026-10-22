// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// A yes or no per id is a set of ids, a BitSet, which only rises; never an
// array of bools beside it.

#include "idr/Support/Id.h"

#include <cstdint>

struct Things {
  struct Minter;
};
using Thing = idr::Id<Things>;
struct Things::Minter {
  static idr::Count<Thing> count(std::uint32_t n) { return idr::Count<Thing>(n); }
};

void sets() {
  idr::BitSet<Thing> marked(Things::Minter::count(4));
  // expected-error@idr/Support/Id.h:* {{a set of ids is a BitSet}}
  idr::IndexVector<Thing, bool> flags(Things::Minter::count(4));
}
