// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The runtime archives the build made, by the SHA-256 digests of their
// files: the runtime, whose native code idris-mlir links and its folders
// run, which every program links; and the checked runtime, the same units
// told to keep a dead cell's memory and end a program that counts it,
// which tests compile programs with. A compilation joins a runtime read
// from one of them and from no other archive (idr/Driver/Runtime.h). The
// list is idris-mlir's own unit, which the build writes whenever an
// archive is (foreign/idr/RuntimeDigest.cmake); this header needs nothing
// the driver's library alone is compiled with, so that unit includes it.
#ifndef IDR_DRIVER_BUILTRUNTIME_H
#define IDR_DRIVER_BUILTRUNTIME_H

#include "llvm/ADT/ArrayRef.h"
#include "llvm/ADT/StringRef.h"

namespace idr::driver {

// One archive the build made: its file's name and its digest, in lowercase
// hex.
struct BuiltArchive {
  llvm::StringLiteral name;
  llvm::StringLiteral digest;
};

llvm::ArrayRef<BuiltArchive> builtArchives();

} // namespace idr::driver

#endif // IDR_DRIVER_BUILTRUNTIME_H
