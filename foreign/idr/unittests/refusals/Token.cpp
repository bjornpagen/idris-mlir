// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// A reuse token is a dead cell held for one construction: it moves along
// counting's walk and is used once, so it is never copied, by construction
// or by assignment.

#include "idr/IR/Quantities.h"

#include <utility>

idr::Token moved(idr::Token held) { return idr::Token(std::move(held)); }

void copied(const idr::Token &held) {
  idr::Token twice(held); // expected-error {{a token is used once}}
}

void assigned(idr::Token &into, const idr::Token &held) {
  into = held; // expected-error {{a token is used once}}
}
