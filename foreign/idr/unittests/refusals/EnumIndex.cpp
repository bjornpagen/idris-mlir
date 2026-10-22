// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// A table over a closed set is indexed by the set's enum, never by the
// position a case happens to have.

#include "idr/Support/Enum.h"

#include <cstddef>

enum class Three : unsigned char { A, B, C };
template <>
struct idr::EnumTraits<Three> {
  static constexpr std::size_t count = 3;
};

int byCase(const idr::EnumArray<Three, int> &table) { return table[Three::C]; }

int byPosition(const idr::EnumArray<Three, int> &table) {
  return table[2]; // expected-error {{index by the enum}}
}
