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

// IO in the world's order, and for a string read its allocation.
void BufferLoadOp::getEffects(
    SmallVectorImpl<SideEffects::EffectInstance<MemoryEffects::Effect>> &effects) {
  ioEffects(Value(), effects);
}
void BufferStoreOp::getEffects(
    SmallVectorImpl<SideEffects::EffectInstance<MemoryEffects::Effect>> &effects) {
  ioEffects(Value(), effects);
}
void BufferCopyOp::getEffects(
    SmallVectorImpl<SideEffects::EffectInstance<MemoryEffects::Effect>> &effects) {
  ioEffects(Value(), effects);
}
void BufferSetStringOp::getEffects(
    SmallVectorImpl<SideEffects::EffectInstance<MemoryEffects::Effect>> &effects) {
  ioEffects(Value(), effects);
}
void BufferGetStringOp::getEffects(
    SmallVectorImpl<SideEffects::EffectInstance<MemoryEffects::Effect>> &effects) {
  ioEffects(getStr(), effects);
}
void WriteBytesOp::getEffects(
    SmallVectorImpl<SideEffects::EffectInstance<MemoryEffects::Effect>> &effects) {
  ioEffects(Value(), effects);
}
void ReadBytesOp::getEffects(
    SmallVectorImpl<SideEffects::EffectInstance<MemoryEffects::Effect>> &effects) {
  ioEffects(Value(), effects);
}
