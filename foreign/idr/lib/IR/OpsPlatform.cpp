// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// What the ops on the platform compute: idr.os, folded to the string of the
// operating system the target triple names. The buffer and byte transfer
// ops declare their buffers, their effects and their guards in ODS
// (IdrIOOps.td).

#include "idr/IR/IdrDialect.h"
// The target entry's triple, generated from CMakeLists.txt.
#include "idr/TargetEntry.h"

#include "mlir/Dialect/LLVMIR/LLVMDialect.h"
#include "llvm/TargetParser/Triple.h"

using namespace mlir;
using namespace idr;

namespace {

// The operating system as Idris's Scheme backends spell it: Linux and the
// BSDs are "unix", Apple's are "darwin", Windows is "windows".
StringRef osName(const llvm::Triple &triple) {
  if (triple.isOSDarwin())
    return "darwin";
  if (triple.isOSLinux() || triple.isOSFreeBSD() || triple.isOSOpenBSD() || triple.isOSNetBSD())
    return "unix";
  if (triple.isOSWindows() || triple.isOSCygMing())
    return "windows";
  return "unknown";
}

} // namespace

// The triple is the module's, as idr-target wrote it before any step ran.
// A module without one, a dialect test's, has the build's, which is the
// triple idr-target writes.
OpFoldResult OsOp::fold(FoldAdaptor) {
  StringRef triple = IDRIS_MLIR_TARGET_TRIPLE;
  if (auto module = (*this)->getParentOfType<ModuleOp>())
    if (auto target =
            module->getAttrOfType<LLVM::TargetAttr>(LLVM::LLVMDialect::getTargetAttrName()))
      triple = target.getTriple().getValue();
  return StringAttr::get(getContext(), osName(llvm::Triple(triple)));
}
