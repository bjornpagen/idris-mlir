// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
static cl::opt<unsigned> inlineLimit(
    "inline-limit",
    cl::desc("The most ops a callee may hold to be inlined"), cl::init(100));
