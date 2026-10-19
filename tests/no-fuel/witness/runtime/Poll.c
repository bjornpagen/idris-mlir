// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
void poll(volatile int *flag) {
  while(1) { if (*flag) break; }
}
