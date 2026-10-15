// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// What the ops on the platform compute: idr.os, folded to the string of the
// operating system the target triple names; and the buffer and byte
// transfer ops, a machine word at a byte offset, a copy, a string written
// or read, the bytes of a buffer read or written. A range is what the
// program computed, so it may lie outside the buffer; idr.check.range
// checks it before the op, which then reads and writes only inside it.

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

// Every buffer holds bytes.
LogicalResult verifyBuffer(Operation *op, Value buffer) {
  auto array = dyn_cast<MemRefType>(unrestricted(buffer.getType()));
  if (!array || !array.getElementType().isInteger(8))
    return op->emitOpError("operates on a buffer of i8, not ") << buffer.getType();
  return success();
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

LogicalResult BufferLoadOp::verify() { return verifyBuffer(*this, getBuffer()); }
LogicalResult BufferStoreOp::verify() { return verifyBuffer(*this, getBuffer()); }
LogicalResult BufferSetStringOp::verify() { return verifyBuffer(*this, getBuffer()); }
LogicalResult BufferGetStringOp::verify() { return verifyBuffer(*this, getBuffer()); }

LogicalResult BufferCopyOp::verify() {
  if (failed(verifyBuffer(*this, getSrc())))
    return failure();
  return verifyBuffer(*this, getDst());
}

LogicalResult WriteBytesOp::verify() { return verifyBuffer(*this, getBuffer()); }
LogicalResult ReadBytesOp::verify() { return verifyBuffer(*this, getBuffer()); }

// An op on a buffer reads or writes the buffer's own memory, which the
// world's chain orders with every other access to it; a transfer to or from
// a handle is IO besides. A string read from a buffer is a new one.
namespace {

using Effects = SmallVectorImpl<SideEffects::EffectInstance<MemoryEffects::Effect>>;

void reads(OpOperand &buffer, Effects &effects) {
  effects.emplace_back(MemoryEffects::Read::get(), &buffer, SideEffects::DefaultResource::get());
}

void writes(OpOperand &buffer, Effects &effects) {
  effects.emplace_back(MemoryEffects::Write::get(), &buffer, SideEffects::DefaultResource::get());
}

void transfers(Effects &effects) {
  effects.emplace_back(MemoryEffects::Read::get(), IOResource::get());
  effects.emplace_back(MemoryEffects::Write::get(), IOResource::get());
}

} // namespace

void BufferLoadOp::getEffects(Effects &effects) { reads(getBufferMutable(), effects); }
void BufferStoreOp::getEffects(Effects &effects) { writes(getBufferMutable(), effects); }
void BufferCopyOp::getEffects(Effects &effects) {
  reads(getSrcMutable(), effects);
  writes(getDstMutable(), effects);
}
void BufferSetStringOp::getEffects(Effects &effects) { writes(getBufferMutable(), effects); }
void BufferGetStringOp::getEffects(Effects &effects) {
  reads(getBufferMutable(), effects);
  effects.emplace_back(MemoryEffects::Allocate::get(), cast<OpResult>(getStr()),
                       SideEffects::DefaultResource::get());
}
void WriteBytesOp::getEffects(Effects &effects) {
  transfers(effects);
  reads(getBufferMutable(), effects);
}
void ReadBytesOp::getEffects(Effects &effects) {
  transfers(effects);
  writes(getBufferMutable(), effects);
}
