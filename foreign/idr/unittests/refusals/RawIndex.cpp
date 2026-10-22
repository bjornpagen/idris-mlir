// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// A fact per id is found by the id its minter made, never by a raw
// integer, which could be any set's position or none.

#include "idr/Support/Id.h"

#include <cstdint>

struct Things {
  struct Minter;
};
using Thing = idr::Id<Things>;
struct Things::Minter {
  static Thing first() { return Thing(0); }
};

void byId(idr::IndexVector<Thing, int> &facts) { facts[Things::Minter::first()] = 1; }

void written(idr::IndexVector<Thing, int> &facts) {
  facts[0] = 1; // expected-error {{index by the id its minter made}}
}

int read(const idr::IndexVector<Thing, int> &facts) {
  return facts[std::uint32_t{0}]; // expected-error {{index by the id its minter made}}
}

void row(const idr::Ragged<Thing, int> &rows) {
  (void)rows[0]; // expected-error {{index by the id its minter made}}
}
