// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The stack idris-mlir and idris-mlir-opt run on, the runtime's
// reserved-stack runner's: MLIR's parser, printer and walks recurse over
// nested constants, so the stack is committed as it is touched and larger
// than the memory of a machine that compiles, which runs out first. No
// larger, since reserving costs time in proportion to the size, at the start
// and at the exit. PIN(mlir-recursion)
#ifndef IDR_SUPPORT_STACK_H
#define IDR_SUPPORT_STACK_H

#include <cstddef>

namespace idr::support {

// The most the stack may grow to, in bytes.
inline constexpr std::size_t toolStack = std::size_t{1} << 40;

// The inaccessible bytes below it, a fault on which is the stack running
// out.
inline constexpr std::size_t toolStackGuard = std::size_t{1} << 20;

} // namespace idr::support

#endif // IDR_SUPPORT_STACK_H
