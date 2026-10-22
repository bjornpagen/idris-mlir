// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The one answer of a monotone step: whether a set rose or a lattice value
// grew. Every join, every raise of a marking and every solve's round says
// it with this, so a loop runs again only on Yes and a step's answer cannot
// be read as some other truth. MLIR's ChangeResult is MLIR's; the solver
// layer names no MLIR, so it has its own.
#ifndef IDR_SUPPORT_CHANGED_H
#define IDR_SUPPORT_CHANGED_H

namespace idr {

enum class Changed : bool { No, Yes };

// Several steps changed something when any one of them did.
constexpr Changed operator|(Changed a, Changed b) {
  return a == Changed::Yes ? Changed::Yes : b;
}

constexpr Changed &operator|=(Changed &a, Changed b) { return a = a | b; }

} // namespace idr

#endif // IDR_SUPPORT_CHANGED_H
