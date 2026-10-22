// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The checked runtime's count of the cells it holds, for a test of the
// runtime written in C (program.h), which links this with the checked
// runtime: the count is a variable of the runtime's C++, which C cannot
// name.
#include "runtime.h"

extern "C" uint64_t prop_held(void) { return prop::held(); }
