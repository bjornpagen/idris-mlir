// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
constexpr int kSweepRounds = 4;
void sweep(Pass &pass) {
  pass.setMaxIterations(kSweepRounds);
}
