// idr.lower:runtime: what idr-lower adds to a module besides converted ops:
// calls of the runtime's C functions, cells, counting, static data and
// crashes.
module;
// The runtime's C ABI: the size of its words and the stack mark of a cell's
// info are macros.
#include "idris_rt.h"

export module idr.lower:runtime;

import idr.mlir;
import idr.dialect;
import idr.layout;

import :crashMessage;
import :staticData;
import :words;

using namespace mlir;

export namespace idr::lower {

class Runtime {
public:
  Runtime(ModuleOp m, layout::Layouts &l)
      : module(m), llvmTypes(m.getContext(), LowerToLLVMOptions(m.getContext(), DataLayout(m))),
        statics(m, l) {}

  // How convert-to-llvm will convert the memref types idr-lower leaves (an
  // array's view of its elements, :arrayView): the same converter over the
  // module's data layout, so that a descriptor built here is the one it
  // reads.
  const LLVMTypeConverter &llvmTypeConverter() const { return llvmTypes; }

  // Calls the runtime function `name` with `args`, returning `result` (or
  // nothing when it is null). The declaration is added on first use.
  Value call(OpBuilder &b, Location loc, StringRef name, Type result, ValueRange args) {
    SymbolTableCollection &symbols = statics.symbolTables();
    auto callee = symbols.lookupSymbolIn<LLVM::LLVMFuncOp>(module, b.getStringAttr(name));
    if (!callee) {
      OpBuilder::InsertionGuard guard(b);
      b.setInsertionPointToStart(module.getBody());
      Type returns = result ? result : LLVM::LLVMVoidType::get(b.getContext());
      auto type = LLVM::LLVMFunctionType::get(returns, llvm::to_vector(args.getTypes()));
      callee = LLVM::LLVMFuncOp::create(b, module.getLoc(), name, type);
      symbols.getSymbolTable(module).insert(callee);
      // The C ABI has the caller extend an argument narrower than 32 bits, and
      // the runtime's narrow parameters are unsigned (a byte): without
      // zeroext, JIT-compiled code would pass garbage in the upper bits.
      for (auto [i, arg] : llvm::enumerate(args.getTypes()))
        if (auto integer = dyn_cast<IntegerType>(arg); integer && integer.getWidth() < 32)
          callee.setArgAttr(static_cast<unsigned>(i), LLVM::LLVMDialect::getZExtAttrName(), b.getUnitAttr());
      // A crash or an exit does not return, which lets LLVM treat what
      // follows as unreachable without the runtime's bitcode (JIT-compiled
      // code has none).
      if (name == "idris_rt_crash" || name == "idris_rt_crash_str" || name == "idris_rt_io_exit")
        callee.setPassthroughAttr(b.getArrayAttr({b.getStringAttr("noreturn")}));
    }
    auto op = LLVM::CallOp::create(b, loc, callee, args);
    return result ? op.getResult() : Value();
  }

  // A crash at `loc` reporting `cause`: idris_rt_crash, which does not
  // return. In compile-time evaluation it ends the evaluation's child,
  // which reports it to the evaluator.
  void crash(OpBuilder &b, Location loc, StringRef cause) {
    std::string text = crashMessage(loc, cause);
    Value ptr = statics.message(b, loc, text);
    Value len = i64Constant(b, loc, static_cast<int64_t>(text.size()));
    call(b, loc, "idris_rt_crash", Type(), ValueRange{ptr, len});
    // The call is cold, and what leads only to it: LLVM lays the crash
    // checks out of the way of the paths that run. The call site says so
    // itself, since linking the runtime replaces the declaration's
    // attributes by the definition's.
    auto call = cast<LLVM::CallOp>(*std::prev(b.getInsertionPoint()));
    call.setCold(true);
    call.setNoreturn(true);
  }

  // The same, where `condition` holds at runtime.
  void crashIf(OpBuilder &b, Location loc, Value condition, StringRef cause) {
    auto check = scf::IfOp::create(b, loc, condition, /*withElseRegion=*/false);
    OpBuilder::InsertionGuard guard(b);
    b.setInsertionPointToStart(check.thenBlock());
    crash(b, loc, cause);
  }

  // Where code that need not end may go on: an effect no MLIR pass
  // removes, and LLVM keeps too, so a loop that may not terminate stays.
  // llvm.sideeffect is the effect LLVM keeps in place and emits as no
  // instruction, so the body of a loop that may not end never empties. A
  // fence would not do: LLVM hoists it out of the loop. Compile-time
  // evaluation counts a tick of its meter right before it (idr-meter).
  void mayLoop(OpBuilder &b, Location loc) {
    LLVM::CallIntrinsicOp::create(b, loc, b.getStringAttr("llvm.sideeffect"), ValueRange{});
  }

  // A new cell of `size` bytes with its header: count 1 and `info`
  // (idris_rt_cell). In compile-time evaluation's arena the runtime makes
  // it persistent, as everything evaluation makes.
  Value allocate(OpBuilder &b, Location loc, unsigned size, layout::CellInfo info) {
    return call(b, loc, "idris_rt_cell", ptrType(b.getContext()),
                ValueRange{i64Constant(b, loc, size), i32Constant(b, loc, info.word())});
  }

  // Writes the header of a cell: count 1 and `info`.
  void storeHeader(OpBuilder &b, Location loc, Value cell, layout::CellInfo info) {
    LLVM::StoreOp::create(b, loc, i32Constant(b, loc, 1), cell, alignAt(0));
    storeInfo(b, loc, cell, i32Constant(b, loc, info.word()));
  }

  // The info word of a cell's header (offset 4), and its write: a force
  // writes the state a memo cell is in.
  Value loadInfo(OpBuilder &b, Location loc, Value cell) {
    return LLVM::LoadOp::create(b, loc, b.getI32Type(), at(b, loc, cell, 4), alignAt(4));
  }

  void storeInfo(OpBuilder &b, Location loc, Value cell, Value info) {
    LLVM::StoreOp::create(b, loc, info, at(b, loc, cell, 4), alignAt(4));
  }

  void store(OpBuilder &b, Location loc, Value cell, ArrayRef<layout::Slot> slots,
             ValueRange values) {
    for (auto [slot, value] : llvm::zip_equal(slots, values))
      LLVM::StoreOp::create(b, loc, value, at(b, loc, cell, slot.offset), alignAt(slot.offset));
  }

  SmallVector<Value> load(OpBuilder &b, Location loc, Value cell, ArrayRef<layout::Slot> slots) {
    SmallVector<Value> values;
    for (const layout::Slot &slot : slots)
      values.push_back(LLVM::LoadOp::create(b, loc, slot.type, at(b, loc, cell, slot.offset),
                                            alignAt(slot.offset)));
    return values;
  }

  // The address of a word of a cell: a destination.
  Value address(OpBuilder &b, Location loc, Value cell, layout::Slot slot) {
    return at(b, loc, cell, slot.offset);
  }

  // Writes a word at an address `address` gave.
  void storeWord(OpBuilder &b, Location loc, Value address, Value value) {
    LLVM::StoreOp::create(b, loc, value, address, IDRIS_RT_WORD_BYTES);
  }

  // The tag of a box: the low bits of its info word.
  Value loadTag(OpBuilder &b, Location loc, Value cell) {
    return LLVM::AndOp::create(b, loc, loadInfo(b, loc, cell),
                               i32Constant(b, loc, layout::tagMask));
  }

  // One more, or one less, reference for each counted component of a value
  // (idris_rt_inc, idris_rt_dec); `counted` says which components are. In
  // compile-time evaluation's arena every cell is persistent, and both do
  // nothing there.
  void inc(OpBuilder &b, Location loc, ValueRange components, ArrayRef<bool> counted) {
    countEach(b, loc, "idris_rt_inc", components, counted);
  }

  void dec(OpBuilder &b, Location loc, ValueRange components, ArrayRef<bool> counted) {
    countEach(b, loc, "idris_rt_dec", components, counted);
  }

  // Whether the cell holds the only reference to itself, where it may be
  // reused: count 1, and not in a stack frame, whose cell a callee it was
  // lent to must never take over.
  Value exclusive(OpBuilder &b, Location loc, Value cell) {
    Value count = LLVM::LoadOp::create(b, loc, b.getI32Type(), cell, alignAt(0));
    Value info = loadInfo(b, loc, cell);
    Value one = LLVM::ICmpOp::create(b, loc, LLVM::ICmpPredicate::eq, count, i32Constant(b, loc, 1));
    Value stack = LLVM::AndOp::create(b, loc, info, i32Constant(b, loc, IDRIS_RT_STACK_CELL));
    Value heap = LLVM::ICmpOp::create(b, loc, LLVM::ICmpPredicate::eq, stack, i32Constant(b, loc, 0));
    return LLVM::AndOp::create(b, loc, one, heap);
  }

  // The empty value of a counted component: a null pointer, or the word 0.
  Value null(OpBuilder &b, Location loc, Type component) {
    return nullComponent(b, loc, component);
  }

  // Whether a lowered component is static data, which holds no count: the
  // address of a global, or a constant word.
  static bool isStatic(Value component) { return StaticData::isStatic(component); }

  // The components of the constant `value` of type `type`: scalars as LLVM
  // constants, strings, bigs outside the small range and boxes (memo cells
  // among them) as static data. Usable in code and in the initializer of a
  // global.
  SmallVector<Value> constant(OpBuilder &b, Location loc, Attribute value, Type type) {
    return statics.constant(b, loc, value, type);
  }

  // What idr-lower adds once every op is converted: @__idr_release_cafs,
  // which releases what the module's static memo cells hold when the
  // program ends. It names every static memo cell, so it is built after the
  // last constant is lowered, once.
  void finish() {
    OpBuilder b(module.getContext());
    statics.emitReleaseCafs(b);
  }

private:
  // Calls `name` on the pointer of each counted component.
  void countEach(OpBuilder &b, Location loc, StringRef name, ValueRange components,
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

  ModuleOp module;
  LLVMTypeConverter llvmTypes;
  StaticData statics;
};

} // namespace idr::lower
