// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
#include "idris_rt.h"

#include "gmock/gmock.h"

int main(int argc, char **argv) {
  idris_rt_gmp_init();
  testing::InitGoogleMock(&argc, argv);
  return RUN_ALL_TESTS();
}
