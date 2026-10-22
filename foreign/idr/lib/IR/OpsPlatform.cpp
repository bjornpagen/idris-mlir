// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// What the ops on the platform compute that no runtime function does:
// idr.platform.os, the operating system the module's target triple names,
// folded to the string base tests for. The triple is the one place the
// target is decided (the target's entry, which idr-target writes into the
// module before any step runs); a module that names no target has no
// operating system to fold to, and the op stays, never the build machine's.

#include "idr/IR/IdrDialect.h"

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

OpFoldResult PlatformOsOp::fold(FoldAdaptor) {
  auto module = (*this)->getParentOfType<ModuleOp>();
  if (!module)
    return {};
  auto target =
      module->getAttrOfType<LLVM::TargetAttr>(LLVM::LLVMDialect::getTargetAttrName());
  if (!target)
    return {};
  return StringAttr::get(getContext(), osName(llvm::Triple(target.getTriple().getValue())));
}
