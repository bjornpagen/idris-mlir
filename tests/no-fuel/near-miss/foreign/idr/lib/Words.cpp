// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// for (;;) and while (true) in a comment, and setMaxIterations(8)
/* while (1) { kNoLimit } */
static const char *name = "setMaxIterations";
static const char *raw = R"(for (;;) maxNumRewrites)";
int count(int n) {
  int maxIterationsSeen = 0;
  for (int i = 0; i < n; ++i) ++maxIterationsSeen;
  for (; n > 0;) --n;
  bool trueish = n == 0;
  while (trueish) trueish = false;
  while (10 > n) ++n;
  return maxIterationsSeen;
}
