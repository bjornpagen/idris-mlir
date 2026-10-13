// The runtime's C functions as idr-lower calls them, and the crashes it
// reports through them.

#include "idr/IR/IdrDialect.h"
#include "idr/IR/Layout.h"
#include "idr/Conversion/Runtime.h"
#include "idr/Conversion/StaticData.h"
#include "idr/Conversion/Words.h"

#include "mlir/Dialect/LLVMIR/LLVMDialect.h"
#include "mlir/Dialect/SCF/IR/SCF.h"
#include "mlir/IR/Location.h"
#include "llvm/ADT/Twine.h"

// The runtime's C ABI: the size of its words and the stack mark of a cell's
// info are macros.
#include "idris_rt.h"

#include <string>

using namespace mlir;

namespace idr::conversion {

namespace {

// Where in the Idris source `loc` is, as the start of its span.
std::string describe(Location loc) {
  if (auto span = dyn_cast<FileLineColRange>(loc))
    return (span.getFilename().getValue() + ":" + Twine(span.getStartLine()) + ":" +
            Twine(span.getStartColumn()))
        .str();
  if (auto fused = dyn_cast<FusedLoc>(loc))
    for (Location inner : fused.getLocations())
      if (auto text = describe(inner); !text.empty())
        return text;
  if (auto named = dyn_cast<NameLoc>(loc))
    return describe(named.getChildLoc());
  if (auto site = dyn_cast<CallSiteLoc>(loc))
    return describe(site.getCallee());
  return "";
}

// The message of a crash, as the runtime prints it: its cause and the Idris
// location.
std::string crashMessage(Location loc, StringRef cause) {
  std::string where = describe(loc);
  return ("idris-mlir: " + cause + (where.empty() ? "" : " at " + where) + "\n").str();
}

} // namespace

Runtime::Runtime(ModuleOp m, const Layouts &l, SymbolTable &symbols,
                 const DataLayoutAnalysis &dataLayouts)
    : module(m),
      llvmTypes(m.getContext(), LowerToLLVMOptions(m.getContext(), dataLayouts.getAtOrAbove(m)),
                &dataLayouts),
      statics(m, l, symbols) {}

Value Runtime::call(OpBuilder &b, Location loc, StringRef name, Type result, ValueRange args) {
  LLVM::CallOp op = callOp(b, loc, name, result, args);
  return result ? op.getResult() : Value();
}

LLVM::CallOp Runtime::callOp(OpBuilder &b, Location loc, StringRef name, Type result,
                             ValueRange args) {
  SymbolTable &table = symbols();
  auto callee = table.lookup<LLVM::LLVMFuncOp>(name);
  if (!callee) {
    OpBuilder::InsertionGuard guard(b);
    b.setInsertionPointToStart(module.getBody());
    Type returns = result ? result : LLVM::LLVMVoidType::get(b.getContext());
    auto type = LLVM::LLVMFunctionType::get(returns, llvm::to_vector(args.getTypes()));
    callee = LLVM::LLVMFuncOp::create(b, module.getLoc(), name, type);
    table.insert(callee);
    // The C ABI has the caller extend an argument narrower than 32 bits, and
    // the runtime's narrow parameters are unsigned (a byte): without
    // zeroext, a caller would pass garbage in the upper bits.
    for (auto [i, arg] : llvm::enumerate(args.getTypes()))
      if (auto integer = dyn_cast<IntegerType>(arg); integer && integer.getWidth() < 32)
        callee.setArgAttr(static_cast<unsigned>(i), LLVM::LLVMDialect::getZExtAttrName(),
                          b.getUnitAttr());
    // A crash or an exit does not return, which lets LLVM treat what
    // follows as unreachable.
    if (name == "idris_rt_crash" || name == "idris_rt_crash_str" || name == "idris_rt_io_exit")
      callee.setNoreturn(true);
  }
  return LLVM::CallOp::create(b, loc, callee, args);
}

void Runtime::crash(OpBuilder &b, Location loc, StringRef cause) {
  std::string text = crashMessage(loc, cause);
  Value ptr = statics.message(b, loc, text);
  Value len = i64Constant(b, loc, static_cast<int64_t>(text.size()));
  // The call is cold, and what leads only to it: LLVM lays the crash
  // checks out of the way of the paths that run. The call site says so
  // itself, since linking the runtime replaces the declaration's
  // attributes by the definition's.
  LLVM::CallOp call = callOp(b, loc, "idris_rt_crash", Type(), ValueRange{ptr, len});
  call.setCold(true);
  call.setNoreturn(true);
}

void Runtime::crashIf(OpBuilder &b, Location loc, Value condition, StringRef cause) {
  auto check = scf::IfOp::create(b, loc, condition, /*withElseRegion=*/false);
  OpBuilder::InsertionGuard guard(b);
  b.setInsertionPointToStart(check.thenBlock());
  crash(b, loc, cause);
}

// llvm.sideeffect is the effect LLVM keeps in place and emits as no
// instruction, so the body of a loop that may not end never empties. A
// fence would not do: LLVM hoists it out of the loop.
void Runtime::mayLoop(OpBuilder &b, Location loc) {
  LLVM::CallIntrinsicOp::create(b, loc, b.getStringAttr("llvm.sideeffect"), ValueRange{});
}

Value Runtime::allocate(OpBuilder &b, Location loc, unsigned size, layout::CellInfo info) {
  return call(b, loc, "idris_rt_cell", ptrType(b.getContext()),
              ValueRange{i64Constant(b, loc, size), i32Constant(b, loc, info.word())});
}

void Runtime::storeHeader(OpBuilder &b, Location loc, Value cell, layout::CellInfo info) {
  LLVM::StoreOp::create(b, loc, i32Constant(b, loc, 1), cell, alignAt(0));
  storeInfo(b, loc, cell, i32Constant(b, loc, info.word()));
}

Value Runtime::loadInfo(OpBuilder &b, Location loc, Value cell) {
  return LLVM::LoadOp::create(b, loc, b.getI32Type(), at(b, loc, cell, 4), alignAt(4));
}

void Runtime::storeInfo(OpBuilder &b, Location loc, Value cell, Value info) {
  LLVM::StoreOp::create(b, loc, info, at(b, loc, cell, 4), alignAt(4));
}

void Runtime::store(OpBuilder &b, Location loc, Value cell, ArrayRef<layout::Slot> slots,
                    ValueRange values) {
  for (auto [slot, value] : llvm::zip_equal(slots, values))
    LLVM::StoreOp::create(b, loc, value, at(b, loc, cell, slot.offset), alignAt(slot.offset));
}

SmallVector<Value> Runtime::load(OpBuilder &b, Location loc, Value cell,
                                 ArrayRef<layout::Slot> slots) {
  SmallVector<Value> values;
  for (const layout::Slot &slot : slots)
    values.push_back(LLVM::LoadOp::create(b, loc, slot.type, at(b, loc, cell, slot.offset),
                                          alignAt(slot.offset)));
  return values;
}

void Runtime::storeWord(OpBuilder &b, Location loc, Value address, Value value) {
  LLVM::StoreOp::create(b, loc, value, address, IDRIS_RT_WORD_BYTES);
}

Value Runtime::loadTag(OpBuilder &b, Location loc, Value cell) {
  return LLVM::AndOp::create(b, loc, loadInfo(b, loc, cell), i32Constant(b, loc, layout::tagMask));
}

void Runtime::inc(OpBuilder &b, Location loc, ValueRange components, ArrayRef<bool> counted) {
  countEach(b, loc, "idris_rt_inc", components, counted);
}

void Runtime::dec(OpBuilder &b, Location loc, ValueRange components, ArrayRef<bool> counted) {
  countEach(b, loc, "idris_rt_dec", components, counted);
}

Value Runtime::exclusive(OpBuilder &b, Location loc, Value cell) {
  Value count = LLVM::LoadOp::create(b, loc, b.getI32Type(), cell, alignAt(0));
  Value info = loadInfo(b, loc, cell);
  Value one = LLVM::ICmpOp::create(b, loc, LLVM::ICmpPredicate::eq, count, i32Constant(b, loc, 1));
  Value stack = LLVM::AndOp::create(b, loc, info, i32Constant(b, loc, IDRIS_RT_STACK_CELL));
  Value heap = LLVM::ICmpOp::create(b, loc, LLVM::ICmpPredicate::eq, stack, i32Constant(b, loc, 0));
  return LLVM::AndOp::create(b, loc, one, heap);
}

SmallVector<Value> Runtime::constant(OpBuilder &b, Location loc, Attribute value, Type type) {
  return statics.constant(b, loc, value, type);
}

void Runtime::finish() {
  OpBuilder b(module.getContext());
  statics.emitReleaseCafs(b);
}

void Runtime::countEach(OpBuilder &b, Location loc, StringRef name, ValueRange components,
                        ArrayRef<bool> counted) {
  for (auto [component, isCounted] : llvm::zip_equal(components, counted)) {
    if (!isCounted)
      continue;
    Value pointer = component;
    if (!isa<LLVM::LLVMPointerType>(pointer.getType()))
      pointer = LLVM::IntToPtrOp::create(b, loc, ptrType(b.getContext()), pointer);
    call(b, loc, name, Type(), pointer);
  }
}

} // namespace idr::conversion
