// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
void wait(volatile int *flag) {
  while (true) if (*flag) return;
}
