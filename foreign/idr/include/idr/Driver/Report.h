// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The tool's name, and the command line's usage errors, which idris-mlir
// prints itself before any compilation has a diagnostic engine: the tool's
// name, the message, a newline. Every later failure is a diagnostic of
// MLIR's engine, which the driver's printer writes in this same shape
// (Diagnostics, Compile.h). The exit status is the caller's; a signal
// handler cannot use this, and writes the same words itself.
#ifndef IDR_DRIVER_REPORT_H
#define IDR_DRIVER_REPORT_H

#include "llvm/ADT/StringRef.h"
#include "llvm/Support/raw_ostream.h"

// The executable's name, as the build names it: each tool's unit is told
// its own, and so is the driver's library, which idris-mlir alone links.
#ifndef IDR_TOOL_NAME
#error "the build gives each tool its executable's name (IDR_TOOL_NAME)"
#endif

namespace idr::driver {

// The tool's name, which every message it writes begins with, and every
// message of the runtime it runs on (runTool, Tool.h).
inline constexpr llvm::StringLiteral toolName = IDR_TOOL_NAME;

// `<tool>: <what is streamed>`, then a newline. A temporary lives for the
// whole statement, so the newline follows the last piece.
struct Report {
  Report() { llvm::errs() << toolName << ": "; }
  ~Report() { llvm::errs() << '\n'; }
  Report(const Report &) = delete;
  Report &operator=(const Report &) = delete;

  template <typename T>
  Report &operator<<(const T &value) {
    llvm::errs() << value;
    return *this;
  }
};

} // namespace idr::driver

#endif // IDR_DRIVER_REPORT_H
