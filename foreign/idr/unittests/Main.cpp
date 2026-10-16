// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// NEEDS-ACCEPTANCE: that googletest and googlemock from the pinned tree build and link under the profile on both targets, and that each box runs every test of its units.
#include "idris_rt.h"

#include "gmock/gmock.h"

int main(int argc, char **argv) {
  idris_rt_gmp_init();
  testing::InitGoogleMock(&argc, argv);
  return RUN_ALL_TESTS();
}
