// idr.lower:runtime: what idr-lower adds to a module besides converted ops:
// calls of the runtime's C functions, cells, counting, static data and
// crashes, in executable or JIT mode.
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
  Runtime(ModuleOp m, layout::Layouts &l, bool jitMode)
      : module(m), layouts(l), jit(jitMode),
        llvmTypes(m.getContext(), LowerToLLVMOptions(m.getContext(), DataLayout(m))),
        statics(m, l) {}

  // Whether the code is lowered for compile-time evaluation, where every
  // cell comes from the arena and is never counted.
  bool isJit() const { return jit; }

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
      // A crash does not return, which lets LLVM treat what follows as
      // unreachable without the runtime's bitcode (JIT mode has none).
      if (name == "idris_rt_crash" || name == "idris_rt_crash_str" || name == "idris_rt_eval_crash")
        callee.setPassthroughAttr(b.getArrayAttr({b.getStringAttr("noreturn")}));
    }
    auto op = LLVM::CallOp::create(b, loc, callee, args);
    return result ? op.getResult() : Value();
  }

  // A crash at `loc` reporting `cause`: idris_rt_crash, or in
  // JIT mode idris_rt_eval_crash, neither of which returns.
  void crash(OpBuilder &b, Location loc, StringRef cause) {
    std::string text = crashMessage(loc, cause);
    Value ptr = statics.message(b, loc, text);
    Value len = i64Constant(b, loc, static_cast<int64_t>(text.size()));
    call(b, loc, jit ? "idris_rt_eval_crash" : "idris_rt_crash", Type(), ValueRange{ptr, len});
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
  // removes, and LLVM keeps too, so a loop that may not terminate stays. In
  // JIT mode it is a tick of the evaluator's meter, which is what stops a
  // metered call that does not end.
  void mayLoop(OpBuilder &b, Location loc) {
    if (jit) {
      call(b, loc, "idris_rt_eval_tick", Type(), ValueRange{});
      return;
    }
    // llvm.sideeffect is the effect LLVM keeps in place and emits as no
    // instruction, so the body of a loop that may not end never empties. A
    // fence would not do: LLVM hoists it out of the loop.
    LLVM::CallIntrinsicOp::create(b, loc, b.getStringAttr("llvm.sideeffect"), ValueRange{});
  }

  // A new cell of `size` bytes with its header: count 1 and `info`
  // (idris_rt_cell), or in JIT mode an arena cell with count 0, which is
  // never counted.
  Value allocate(OpBuilder &b, Location loc, unsigned size, layout::CellInfo info) {
    if (!jit)
      return call(b, loc, "idris_rt_cell", ptrType(b.getContext()),
                  ValueRange{i64Constant(b, loc, size), i32Constant(b, loc, info.word())});
    Value cell = call(b, loc, "idris_rt_arena_alloc", ptrType(b.getContext()),
                      i64Constant(b, loc, size));
    storeHeader(b, loc, cell, info);
    return cell;
  }

  // Writes the header of a cell: count 1 and `info`. Count 0 in JIT mode:
  // the arena's cells are persistent, as everything compile-time evaluation
  // makes.
  void storeHeader(OpBuilder &b, Location loc, Value cell, layout::CellInfo info) {
    LLVM::StoreOp::create(b, loc, i32Constant(b, loc, jit ? 0 : 1), cell, alignAt(0));
    LLVM::StoreOp::create(b, loc, i32Constant(b, loc, info.word()), at(b, loc, cell, 4), alignAt(4));
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

  // The tag of a box: the low bits of its info word (offset 4).
  Value loadTag(OpBuilder &b, Location loc, Value cell) {
    Value info = LLVM::LoadOp::create(b, loc, b.getI32Type(), at(b, loc, cell, 4), alignAt(4));
    return LLVM::AndOp::create(b, loc, info, i32Constant(b, loc, layout::tagMask));
  }

  // One more, or one less, reference for each counted component of a value
  // (idris_rt_inc, idris_rt_dec); `counted` says which components are. In
  // JIT mode every cell is persistent, and both do nothing.
  void inc(OpBuilder &b, Location loc, ValueRange components, ArrayRef<bool> counted) {
    if (!jit)
      countEach(b, loc, "idris_rt_inc", components, counted);
  }

  void dec(OpBuilder &b, Location loc, ValueRange components, ArrayRef<bool> counted) {
    if (!jit)
      countEach(b, loc, "idris_rt_dec", components, counted);
  }

  // Whether the cell holds the only reference to itself, where it may be
  // reused: count 1, and not in a stack frame, whose cell a callee it was
  // lent to must never take over.
  Value exclusive(OpBuilder &b, Location loc, Value cell) {
    Value count = LLVM::LoadOp::create(b, loc, b.getI32Type(), cell, alignAt(0));
    Value info = LLVM::LoadOp::create(b, loc, b.getI32Type(), at(b, loc, cell, 4), alignAt(4));
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

  // The components of the constant `value` of type `type`:
  // scalars as LLVM constants, strings, bigs outside the small range, boxes
  // and closures as static data. Usable in code and in the initializer of a
  // global.
  SmallVector<Value> constant(OpBuilder &b, Location loc, Attribute value, Type type) {
    return statics.constant(b, loc, value, type);
  }

  // The address of the code of `label`'s closures: a function taking the
  // closure, then the arguments.
  Value code(OpBuilder &b, Location loc, const layout::Label &label) {
    return statics.code(b, loc, label);
  }

  // The type of that code, and the code itself, once the functions have
  // their converted signatures.
  FunctionType codeType(const layout::Label &label) { return statics.codeType(label); }

  // Loads the captures from the closure, then calls the label's function with
  // them before the arguments. A suspension's code pointer is its state:
  // the first entry computes the value, writes it over the payload and
  // replaces the pointer, and every later entry returns what was written.
  void emitCode() {
    SymbolTableCollection &symbols = statics.symbolTables();
    OpBuilder b(module.getContext());
    b.setInsertionPointToEnd(module.getBody());
    for (unsigned id : statics.usedLabels()) {
      const layout::Label &label = layouts.label(id);
      if (const layout::Cell *evaluated = layouts.forced(id))
        emitSuspension(b, symbols, id, label, *evaluated);
      else
        emitClosure(b, symbols, id, label);
    }
  }

private:
  void emitClosure(OpBuilder &b, SymbolTableCollection &symbols, unsigned id,
                   const layout::Label &label) {
    const layout::Cell &cell = layouts.closure(label);
    auto callee = symbols.lookupSymbolIn<func::FuncOp>(module, label.callee);
    Location loc = callee.getLoc();
    FunctionType type = codeType(label);
    auto fn = func::FuncOp::create(b, loc, layout::codeName(id), type);
    symbols.getSymbolTable(module).insert(fn);
    fn.setPrivate();
    OpBuilder::InsertionGuard guard(b);
    Block *entry = fn.addEntryBlock();
    b.setInsertionPointToStart(entry);
    // Two entries that differ only by which function they call are the same
    // bytes apart from those names, and identical code folding keeps one.
    // The label is a constant in the body, so each entry stays its own.
    distinguish(b, loc, id);
    // The closure keeps its captures, and the function takes each owned:
    // one more reference each.
    SmallVector<Value> args;
    for (auto [capture, captureType] :
         llvm::zip_equal(ArrayRef(cell.fields).drop_front(), label.captureTypes())) {
      SmallVector<Value> components = load(b, loc, entry->getArgument(0), capture);
      inc(b, loc, components, layouts.counted(captureType));
      llvm::append_range(args, components);
    }
    llvm::append_range(args, entry->getArguments().drop_front());
    auto result = func::CallOp::create(b, loc, callee, args);
    func::ReturnOp::create(b, loc, result.getResults());
  }

  // The address of the entry that returns a suspension's stored value.
  Value doneCode(OpBuilder &b, Location loc, FunctionType type, unsigned id) {
    Value function = func::ConstantOp::create(b, loc, type, layout::lazyDoneName(id));
    return UnrealizedConversionCastOp::create(b, loc, ptrType(b.getContext()), function).getResult(0);
  }

  // The info word of the stored value, keeping a stack mark if the cell
  // has one: the count stays, and free still reads the new object slots.
  void storeForcedInfo(OpBuilder &b, Location loc, Value cell, layout::CellInfo info) {
    Value old = LLVM::LoadOp::create(b, loc, b.getI32Type(), at(b, loc, cell, 4), alignAt(4));
    Value stack = LLVM::AndOp::create(b, loc, old, i32Constant(b, loc, IDRIS_RT_STACK_CELL));
    Value word = arith::OrIOp::create(b, loc, i32Constant(b, loc, info.word()), stack);
    LLVM::StoreOp::create(b, loc, word, at(b, loc, cell, 4), alignAt(4));
  }

  void emitSuspension(OpBuilder &b, SymbolTableCollection &symbols, unsigned id,
                      const layout::Label &label, const layout::Cell &evaluated) {
    const layout::Cell &uneval = layouts.closure(label);
    auto callee = symbols.lookupSymbolIn<func::FuncOp>(module, label.callee);
    Location loc = callee.getLoc();
    FunctionType type = codeType(label);
    Type resultType = label.type.getResult(0);
    auto done = func::FuncOp::create(b, loc, layout::lazyDoneName(id), type);
    auto enter = func::FuncOp::create(b, loc, layout::codeName(id), type);
    symbols.getSymbolTable(module).insert(done);
    symbols.getSymbolTable(module).insert(enter);
    done.setPrivate();
    enter.setPrivate();
    ArrayRef<layout::Slot> resultSlots =
        evaluated.fields.size() > 1 ? ArrayRef<layout::Slot>(evaluated.fields[1])
                                    : ArrayRef<layout::Slot>();
    {
      OpBuilder::InsertionGuard guard(b);
      Block *entry = done.addEntryBlock();
      b.setInsertionPointToStart(entry);
      SmallVector<Value> result = load(b, loc, entry->getArgument(0), resultSlots);
      inc(b, loc, result, layouts.counted(resultType));
      func::ReturnOp::create(b, loc, result);
    }
    {
      OpBuilder::InsertionGuard guard(b);
      Block *entry = enter.addEntryBlock();
      b.setInsertionPointToStart(entry);
      // Same as a closure's entry: the label is in the body, or folding
      // would run one suspension's value for another.
      distinguish(b, loc, id);
      Value cell = entry->getArgument(0);
      // The cell keeps its captures. The function takes an owned copy of
      // each, so one more reference, released with the cell's own after
      // the value is in hand: a value that is a capture is not freed
      // before it is stored.
      SmallVector<Value> args;
      SmallVector<SmallVector<Value>> held;
      SmallVector<Type> heldTypes;
      for (auto [capture, captureType] :
           llvm::zip_equal(ArrayRef(uneval.fields).drop_front(), label.captureTypes())) {
        SmallVector<Value> components = load(b, loc, cell, capture);
        inc(b, loc, components, layouts.counted(captureType));
        held.push_back(components);
        heldTypes.push_back(captureType);
        llvm::append_range(args, components);
      }
      auto result = func::CallOp::create(b, loc, callee, args);
      inc(b, loc, result.getResults(), layouts.counted(resultType));
      for (auto [components, captureType] : llvm::zip_equal(held, heldTypes))
        dec(b, loc, components, layouts.counted(captureType));
      store(b, loc, cell, resultSlots, result.getResults());
      store(b, loc, cell, evaluated.fields.front(), doneCode(b, loc, type, id));
      storeForcedInfo(b, loc, cell, evaluated.info);
      // A persistent cell is never freed, so the value it now owns would
      // outlive the program. The runtime notes it and releases that value
      // when main returns. Counted cells release theirs when they are freed.
      if (!jit)
        call(b, loc, "idris_rt_lazy_kept", Type(), cell);
      func::ReturnOp::create(b, loc, result.getResults());
    }
  }

  // Writes `id` where a later pass cannot drop it and identical code
  // folding cannot treat it as a relocation. The slot is otherwise unused.
  void distinguish(OpBuilder &b, Location loc, unsigned id) {
    Value one = LLVM::ConstantOp::create(b, loc, b.getI64Type(), b.getI64IntegerAttr(1));
    Value slot = LLVM::AllocaOp::create(b, loc, ptrType(b.getContext()), b.getI32Type(), one,
                                        /*alignment=*/4);
    LLVM::StoreOp::create(b, loc, i32Constant(b, loc, static_cast<int64_t>(id)), slot,
                          /*alignment=*/4, /*isVolatile=*/true);
  }

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
  layout::Layouts &layouts;
  bool jit;
  LLVMTypeConverter llvmTypes;
  StaticData statics;
};

} // namespace idr::lower
