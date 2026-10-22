// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
/* The runtime's link check. runtime/CMakeLists.txt links every
 * member of the runtime archive into this program, as an executable of
 * the target (its entry's executable flags) with no C++ library and no
 * unwinder: a reference to the C++
 * runtime is an undefined symbol, so the link, and the build, fail. What
 * the driver writes for every program after its code, the program's built
 * facts, which the runtime's entry reads, a program of nothing gives here. */
#include "idris_rt.h"

const idris_rt_built idris_rt_program_built = {0, 0, 0, "link_check", 10};

int main(void) { return 0; }
