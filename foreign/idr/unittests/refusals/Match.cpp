// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// A match over a closed sum has a case for every alternative, and every
// case gives one type: a sum that gains an alternative is refused at every
// match that forgot it.

#include "idr/Support/Match.h"

#include <string>
#include <variant>

using Sum = std::variant<int, std::string>;

int whole(const Sum &sum) {
  return idr::match(sum, [](int) { return 0; }, [](const std::string &) { return 1; });
}

void missing(const Sum &sum) {
  // expected-error@idr/Support/Match.h:* {{a match has a case for every alternative}}
  idr::match(sum, [](int) {});
}

void twoTypes(const Sum &sum) {
  // expected-error@idr/Support/Match.h:* {{every case of a match gives one type}}
  idr::match(sum, [](int) { return 0; }, [](const std::string &) { return 0.5; });
}
