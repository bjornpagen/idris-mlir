// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The command line's usage errors, which idris-mlir prints itself before
// any compilation has a diagnostic engine: the tool's name, the message, a
// newline. Every later failure is a diagnostic of MLIR's engine, which the
// driver's printer writes in this same shape (Diagnostics, Compile.h). The
// exit status is the caller's; a signal handler cannot use this, and
// writes the same words itself.
#ifndef IDR_DRIVER_REPORT_H
#define IDR_DRIVER_REPORT_H

#include "llvm/Support/raw_ostream.h"

namespace idr::driver {

// `idris-mlir: <what is streamed>`, then a newline. A temporary lives for
// the whole statement, so the newline follows the last piece.
struct Report {
  Report() { llvm::errs() << "idris-mlir: "; }
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
