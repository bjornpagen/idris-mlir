// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// A scalar's UTF-8 bytes.
// PIN(runtime-quarantine) — see PINS.md
#include "Strings/Strings.h"

#include <stddef.h>
#include <stdint.h>

namespace rt::strings {

size_t encodeUtf8(int32_t c, char *out) {
  auto u = static_cast<uint32_t>(c);
  if (u < 0x80) {
    out[0] = static_cast<char>(u);
    return 1;
  }
  size_t n = u < 0x800 ? 2 : u < 0x10000 ? 3 : 4;
  static constexpr uint32_t prefix[] = {0, 0, 0xC0, 0xE0, 0xF0};
  out[0] = static_cast<char>(prefix[n] | (u >> (6 * (n - 1))));
  for (size_t k = 1; k < n; ++k)
    out[k] = static_cast<char>(0x80 | ((u >> (6 * (n - 1 - k))) & 0x3F));
  return n;
}

} // namespace rt::strings
