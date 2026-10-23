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

#include <optional>

using namespace mlir;
using namespace idr;

namespace {

// The operating system of a target of ours, as Idris's Scheme backends
// spell it for base: macOS is "darwin", Linux "unix". Every target entry
// is one of the two (CMakeLists.txt), and idr-target writes the entry's
// triple over whatever a module held, so a module the compiler compiles
// names one of them. A triple of any other system reaches here only in a
// module written by hand for idris-mlir-opt that skips idr-target: like a
// module that names no target, it has no operating system of ours to fold
// to.
std::optional<StringRef> osName(const llvm::Triple &triple) {
  if (triple.isMacOSX())
    return StringRef("darwin");
  if (triple.isOSLinux())
    return StringRef("unix");
  return std::nullopt;
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
  std::optional<StringRef> os = osName(llvm::Triple(target.getTriple().getValue()));
  if (!os)
    return {};
  return StringAttr::get(getContext(), *os);
}
