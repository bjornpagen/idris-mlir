// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// Every box runs as the tools do, on the runtime's runner, under its own
// executable's name: the runner sets the heap and GMP's allocation up
// before anything of the runtime runs, so every big a box makes, and every
// fold it asks of the runtime, is made where a program's would be.
#include "idr/Driver/Tool.h"

#include "gmock/gmock.h"

int main(int argc, char **argv) {
  return idr::driver::runTool([&] {
    testing::InitGoogleMock(&argc, argv);
    return RUN_ALL_TESTS();
  });
}
