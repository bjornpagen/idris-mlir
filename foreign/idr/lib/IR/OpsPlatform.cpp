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

// A triple of any other system than a target of ours reaches here only in
// a module written by hand for idris-mlir-opt that skips idr-target: like
// a module that names no target, it has no operating system of ours to
// fold to. Every target entry is macOS or Linux (CMakeLists.txt), and
// idr-target writes the entry's triple on a module that names none and
// refuses one that names another, so a module the compiler compiles names
// one of them; macOS is "darwin" and Linux "unix" to base.
std::optional<StringRef> platform::osName(const llvm::Triple &triple) {
  if (triple.isMacOSX())
    return StringRef("darwin");
  if (triple.isOSLinux())
    return StringRef("unix");
  return std::nullopt;
}

std::optional<llvm::Triple> platform::targetOf(Operation *op) {
  auto module = op->getParentOfType<ModuleOp>();
  if (!module)
    return std::nullopt;
  auto target =
      module->getAttrOfType<LLVM::TargetAttr>(LLVM::LLVMDialect::getTargetAttrName());
  if (!target)
    return std::nullopt;
  return llvm::Triple(target.getTriple().getValue());
}

// Its meaning's attribute instance (Ops/Folds.h).
OpFoldResult PlatformOsOp::fold(FoldAdaptor adaptor) {
  fold::InParts where(getContext());
  std::optional<Attribute> folded = meaning(where, *this, adaptor.getOperands());
  return folded ? OpFoldResult(*folded) : OpFoldResult();
}
