// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The program's arguments, which idris_rt_start keeps and rt::io reads, in
// a unit of their own: a tool's folders reach the argument entries, never
// the program's entry.
// PIN(runtime-quarantine) — see PINS.md
#include "Start/Start.h"
#include "idris_rt.h"

#include <stdint.h>
#include <string.h>

namespace {

int32_t total = 0;
char **texts = nullptr;

} // namespace

namespace rt::start {

void keepArguments(int32_t count, char **text) noexcept {
  total = count;
  texts = text;
}

int64_t argumentCount() { return total; }

const idris_rt_str *argument(int64_t i) {
  const char *text = i >= 0 && i < total ? texts[i] : "";
  return idris_rt_str_from_bytes(text, strlen(text));
}

} // namespace rt::start
