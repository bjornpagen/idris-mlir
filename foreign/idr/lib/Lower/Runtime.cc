// Runtime calls, cells, static data and crashes for idr-lower.

#include "Lower/Runtime.h"

#include "idris_rt.h"

#include "mlir/Dialect/Math/IR/Math.h"
#include "mlir/Dialect/SCF/IR/SCF.h"

#include "llvm/ADT/StringExtras.h"

using namespace mlir;

namespace idr::lower {

namespace {

std::string describe(Location loc) {
  if (auto file = dyn_cast<FileLineColLoc>(loc))
    return (file.getFilename().getValue() + ":" + Twine(file.getLine()) + ":" +
            Twine(file.getColumn()))
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

Type ptrType(MLIRContext *ctx) { return LLVM::LLVMPointerType::get(ctx); }

Value i64Constant(OpBuilder &b, Location loc, int64_t value) {
  return LLVM::ConstantOp::create(b, loc, b.getI64Type(), b.getI64IntegerAttr(value));
}

Value i32Constant(OpBuilder &b, Location loc, int64_t value) {
  return LLVM::ConstantOp::create(b, loc, b.getI32Type(),
                                  b.getI32IntegerAttr(static_cast<int32_t>(value)));
}

Value at(OpBuilder &b, Location loc, Value cell, unsigned offset) {
  return LLVM::GEPOp::create(b, loc, ptrType(b.getContext()), b.getI8Type(), cell,
                             ArrayRef<LLVM::GEPArg>{static_cast<int32_t>(offset)});
}

// The alignment of the word at `offset` in a cell, which is 8-aligned: LLVM
// would otherwise take the alignment of the type from a data layout that
// the translation does not have yet.
unsigned alignAt(unsigned offset) { return static_cast<unsigned>(llvm::MinAlign(8, offset)); }

} // namespace

std::string crashMessage(Location loc, StringRef cause) {
  std::string where = describe(loc);
  return ("idris-mlir: " + cause + (where.empty() ? "" : " at " + where) + "\n").str();
}

std::string codeName(unsigned id) { return ("__idr_code_" + Twine(id)).str(); }

Value Runtime::call(OpBuilder &b, Location loc, StringRef name, Type result, ValueRange args) {
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
        callee.setArgAttr(i, LLVM::LLVMDialect::getZExtAttrName(), b.getUnitAttr());
    // A crash does not return, which lets LLVM treat what follows as
    // unreachable without the runtime's bitcode (JIT mode has none).
    if (name == "idris_rt_crash" || name == "idris_rt_eval_crash")
      callee.setPassthroughAttr(b.getArrayAttr({b.getStringAttr("noreturn")}));
  }
  auto op = LLVM::CallOp::create(b, loc, callee, args);
  return result ? op.getResult() : Value();
}

void Runtime::crash(OpBuilder &b, Location loc, StringRef cause) {
  std::string text = crashMessage(loc, cause);
  auto it = messages.find(text);
  LLVM::GlobalOp message;
  if (it != messages.end()) {
    message = it->second;
  } else {
    auto type = LLVM::LLVMArrayType::get(b.getI8Type(), text.size());
    message = global(b, loc, "__idr_msg_", type, [&](OpBuilder &init) -> Value {
      return LLVM::ConstantOp::create(init, loc, type, init.getStringAttr(text));
    });
    messages[text] = message;
  }
  Value ptr = addressOf(b, loc, message);
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

void Runtime::crashIf(OpBuilder &b, Location loc, Value condition, StringRef cause) {
  auto check = scf::IfOp::create(b, loc, condition, /*withElseRegion=*/false);
  OpBuilder::InsertionGuard guard(b);
  b.setInsertionPointToStart(check.thenBlock());
  crash(b, loc, cause);
}

void Runtime::mayLoop(OpBuilder &b, Location loc) {
  if (jit) {
    call(b, loc, "idris_rt_eval_tick", Type(), ValueRange{});
    return;
  }
  // llvm.sideeffect is the effect LLVM keeps in place and emits as no
  // instruction, so the body of a loop that may not end never empties. A
  // fence would not do: LLVM hoists it out of the loop.
  LLVM::CallIntrinsicOp::create(b, loc, b.getStringAttr("llvm.sideeffect"), ValueRange{});
}

Value Runtime::allocate(OpBuilder &b, Location loc, unsigned size, CellInfo info) {
  if (!jit)
    return call(b, loc, "idris_rt_cell", ptrType(b.getContext()),
                ValueRange{i64Constant(b, loc, size), i32Constant(b, loc, info.word())});
  Value cell = call(b, loc, "idris_rt_arena_alloc", ptrType(b.getContext()),
                    i64Constant(b, loc, size));
  storeHeader(b, loc, cell, info);
  return cell;
}

// Count 0 in JIT mode: the arena's cells are persistent, as everything
// compile-time evaluation makes.
void Runtime::storeHeader(OpBuilder &b, Location loc, Value cell, CellInfo info) {
  LLVM::StoreOp::create(b, loc, i32Constant(b, loc, jit ? 0 : 1), cell, alignAt(0));
  LLVM::StoreOp::create(b, loc, i32Constant(b, loc, info.word()), at(b, loc, cell, 4), alignAt(4));
}

void Runtime::store(OpBuilder &b, Location loc, Value cell, ArrayRef<Slot> slots,
                    ValueRange values) {
  for (auto [slot, value] : llvm::zip_equal(slots, values))
    LLVM::StoreOp::create(b, loc, value, at(b, loc, cell, slot.offset), alignAt(slot.offset));
}

SmallVector<Value> Runtime::load(OpBuilder &b, Location loc, Value cell, ArrayRef<Slot> slots) {
  SmallVector<Value> values;
  for (const Slot &slot : slots)
    values.push_back(LLVM::LoadOp::create(b, loc, slot.type, at(b, loc, cell, slot.offset),
                                          alignAt(slot.offset)));
  return values;
}

Value Runtime::loadTag(OpBuilder &b, Location loc, Value cell) {
  Value info = LLVM::LoadOp::create(b, loc, b.getI32Type(), at(b, loc, cell, 4), alignAt(4));
  return LLVM::AndOp::create(b, loc, info, i32Constant(b, loc, tagMask));
}

Value Runtime::exclusive(OpBuilder &b, Location loc, Value cell) {
  Value count = LLVM::LoadOp::create(b, loc, b.getI32Type(), cell, alignAt(0));
  Value info = LLVM::LoadOp::create(b, loc, b.getI32Type(), at(b, loc, cell, 4), alignAt(4));
  Value one = LLVM::ICmpOp::create(b, loc, LLVM::ICmpPredicate::eq, count, i32Constant(b, loc, 1));
  Value stack = LLVM::AndOp::create(b, loc, info, i32Constant(b, loc, IDRIS_RT_STACK_CELL));
  Value heap = LLVM::ICmpOp::create(b, loc, LLVM::ICmpPredicate::eq, stack, i32Constant(b, loc, 0));
  return LLVM::AndOp::create(b, loc, one, heap);
}

Value Runtime::null(OpBuilder &b, Location loc, Type component) {
  if (isa<LLVM::LLVMPointerType>(component))
    return LLVM::ZeroOp::create(b, loc, component);
  return LLVM::ConstantOp::create(b, loc, component, b.getIntegerAttr(component, 0));
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

void Runtime::inc(OpBuilder &b, Location loc, ValueRange components, ArrayRef<bool> counted) {
  if (!jit)
    countEach(b, loc, "idris_rt_inc", components, counted);
}

void Runtime::dec(OpBuilder &b, Location loc, ValueRange components, ArrayRef<bool> counted) {
  if (!jit)
    countEach(b, loc, "idris_rt_dec", components, counted);
}

LLVM::GlobalOp Runtime::global(OpBuilder &b, Location loc, StringRef prefix, Type type,
                               function_ref<Value(OpBuilder &)> init) {
  OpBuilder::InsertionGuard guard(b);
  b.setInsertionPointToStart(module.getBody());
  std::string name = (prefix + Twine(globals++)).str();
  auto global = LLVM::GlobalOp::create(b, loc, type, /*isConstant=*/true, LLVM::Linkage::Private,
                                       name, Attribute(), /*alignment=*/8);
  b.createBlock(&global.getInitializerRegion());
  LLVM::ReturnOp::create(b, loc, init(b));
  return global;
}

Value Runtime::addressOf(OpBuilder &b, Location loc, LLVM::GlobalOp global) {
  return LLVM::AddressOfOp::create(b, loc, global);
}

Value Runtime::pack(OpBuilder &b, Location loc, Type structType, ValueRange members) {
  Value value = LLVM::PoisonOp::create(b, loc, structType);
  for (auto [i, member] : llvm::enumerate(members))
    value = LLVM::InsertValueOp::create(b, loc, value, member, static_cast<int64_t>(i));
  return value;
}

LLVM::GlobalOp Runtime::staticCell(
    OpBuilder &b, Location loc, StringRef prefix, const Cell &cell,
    function_ref<SmallVector<Value>(OpBuilder &, unsigned field)> components) {
  auto structType = LLVM::LLVMStructType::getLiteral(b.getContext(), cell.members(b.getContext()));
  return global(b, loc, prefix, structType, [&](OpBuilder &init) -> Value {
    SmallVector<SmallVector<Value>> fields;
    for (unsigned field = 0; field < cell.fields.size(); ++field)
      fields.push_back(components(init, field));
    SmallVector<Value> members{i32Constant(init, loc, 0), i32Constant(init, loc, cell.info.word())};
    for (auto [field, component] : cell.order)
      members.push_back(fields[field][component]);
    return pack(init, loc, structType, members);
  });
}

// A string: the header (count 0: static data), the byte length and the
// scalar count, which the runtime computes, then the bytes.
Value Runtime::string(OpBuilder &b, Location loc, StringRef bytes) {
  auto key = std::make_pair(Attribute(b.getStringAttr(bytes)), Type(StrType::get(b.getContext())));
  auto it = statics.find(key);
  if (it == statics.end()) {
    auto i32 = b.getI32Type(), i64 = b.getI64Type();
    SmallVector<Type> members{i32, i32, i64, i64};
    if (!bytes.empty())
      members.push_back(LLVM::LLVMArrayType::get(b.getI8Type(), bytes.size()));
    auto type = LLVM::LLVMStructType::getLiteral(b.getContext(), members);
    bool ascii = idris_rt_ascii(bytes.data(), bytes.size());
    auto scalars = static_cast<int64_t>(idris_rt_utf8_count(bytes.data(), bytes.size()));
    uint32_t info = CellInfo::string(ascii).word();
    auto global = this->global(b, loc, "__idr_str_", type, [&](OpBuilder &init) -> Value {
      SmallVector<Value> values{i32Constant(init, loc, 0), i32Constant(init, loc, info),
                                i64Constant(init, loc, static_cast<int64_t>(bytes.size())),
                                i64Constant(init, loc, scalars)};
      if (!bytes.empty())
        values.push_back(
            LLVM::ConstantOp::create(init, loc, members.back(), init.getStringAttr(bytes)));
      return pack(init, loc, type, values);
    });
    it = statics.try_emplace(key, global).first;
  }
  return addressOf(b, loc, it->second);
}

// A big: the runtime reads the decimal text (one semantics for what a
// big literal denotes); a small result is its tagged word, any other a
// static idris_rt_bignum whose limbs are static too.
Value Runtime::big(OpBuilder &b, Location loc, BigAttr value) {
  StringRef text = value.getValue();
  const idris_rt_str *digits = idris_rt_str_from_utf8(text.data(), text.size());
  idris_rt_big word = idris_rt_big_from_str(digits);
  idris_rt_str_release(digits);
  if ((word & 1) != 0) {
    idris_rt_big_release(word);
    return i64Constant(b, loc, word);
  }
  auto key = std::make_pair(Attribute(value), Type(BigType::get(b.getContext())));
  auto it = statics.find(key);
  if (it == statics.end()) {
    const auto *number = reinterpret_cast<const idris_rt_bignum *>(word);
    auto count = static_cast<size_t>(number->size < 0 ? -number->size : number->size);
    SmallVector<int64_t> limbs;
    for (size_t i = 0; i < count; ++i)
      limbs.push_back(static_cast<int64_t>(number->limbs[i]));
    int32_t size = number->size;
    idris_rt_big_release(word);
    auto i32 = b.getI32Type();
    auto limbsType = LLVM::LLVMArrayType::get(b.getI64Type(), count);
    auto limbsGlobal = global(b, loc, "__idr_limbs_", limbsType, [&](OpBuilder &init) -> Value {
      return LLVM::ConstantOp::create(
          init, loc, limbsType,
          DenseElementsAttr::get(
              RankedTensorType::get({static_cast<int64_t>(count)}, init.getI64Type()),
              ArrayRef<int64_t>(limbs)));
    });
    auto type = LLVM::LLVMStructType::getLiteral(b.getContext(),
                                                 {i32, i32, i32, i32, ptrType(b.getContext())});
    auto global = this->global(b, loc, "__idr_big_", type, [&](OpBuilder &init) -> Value {
      return pack(init, loc, type,
                  {i32Constant(init, loc, 0),
                   i32Constant(init, loc, CellInfo::bignum().word()),
                   i32Constant(init, loc, static_cast<int64_t>(count)), i32Constant(init, loc, size),
                   addressOf(init, loc, limbsGlobal)});
    });
    it = statics.try_emplace(key, global).first;
  }
  return LLVM::PtrToIntOp::create(b, loc, b.getI64Type(), addressOf(b, loc, it->second));
}

SmallVector<Value> Runtime::constant(OpBuilder &b, Location loc, Attribute value, Type type) {
  // A linear value is the value itself at runtime.
  type = unrestricted(type);
  if (isa<ErasedType, WorldType>(type))
    return {};
  if (auto text = dyn_cast<StringAttr>(value))
    return {string(b, loc, text.getValue())};
  if (auto number = dyn_cast<BigAttr>(value))
    return {big(b, loc, number)};
  if (isa<IntegerAttr, FloatAttr>(value))
    return {LLVM::ConstantOp::create(b, loc, type, cast<TypedAttr>(value))};
  if (auto data = dyn_cast<DataType>(type)) {
    auto con = cast<ConAttr>(value);
    const SumLayout &layout = layouts.sum(data.getName().getAttr());
    auto ctor = symbols.lookupSymbolIn<CtorOp>(module, con.getCtor());
    SmallVector<Value> slots(layout.slots.size());
    const auto &fields = layout.fields.find(ctor.getSymName())->second;
    for (auto [i, field] : llvm::enumerate(con.getFields()))
      for (auto [slot, component] :
           llvm::zip_equal(fields[i], constant(b, loc, field, ctor.getFieldType(static_cast<unsigned>(i)))))
        slots[slot] = component;
    SmallVector<Value> out;
    if (layout.tag)
      out.push_back(LLVM::ConstantOp::create(b, loc, layout.tag,
                                             b.getIntegerAttr(layout.tag, static_cast<int64_t>(ctor.getTag()))));
    // A counted slot the constructor does not use is empty, so that
    // counting the sum counts each of its slots.
    for (auto [slot, component] : llvm::enumerate(slots))
      out.push_back(component               ? component
                    : layout.counted[slot] ? null(b, loc, layout.slots[slot])
                                           : LLVM::PoisonOp::create(b, loc, layout.slots[slot]).getResult());
    return out;
  }
  auto key = std::make_pair(value, type);
  auto it = statics.find(key);
  if (it == statics.end()) {
    LLVM::GlobalOp cellGlobal;
    if (auto con = dyn_cast<ConAttr>(value)) {
      auto ctor = symbols.lookupSymbolIn<CtorOp>(module, con.getCtor());
      const Cell &cell = layouts.box(ctor);
      cellGlobal = staticCell(b, loc, "__idr_box_", cell, [&](OpBuilder &init, unsigned i) {
        return constant(init, loc, con.getFields()[i], ctor.getFieldType(i));
      });
    } else {
      auto closure = cast<ClosureAttr>(value);
      const Label &label = layouts.label(layouts.labelId(
          closure.getCallee(), static_cast<unsigned>(closure.getCaptures().size())));
      const Cell &cell = layouts.closure(label);
      cellGlobal = staticCell(b, loc, "__idr_closure_", cell,
                              [&](OpBuilder &init, unsigned i) -> SmallVector<Value> {
                                if (i == 0)
                                  return {code(init, loc, label)};
                                return constant(init, loc, closure.getCaptures()[i - 1],
                                                label.captureTypes()[i - 1]);
                              });
    }
    it = statics.try_emplace(key, cellGlobal).first;
  }
  return {addressOf(b, loc, it->second)};
}

FunctionType Runtime::codeType(const Label &label) {
  SmallVector<Type> inputs{ptrType(module.getContext())};
  for (Type input : label.argumentTypes())
    llvm::append_range(inputs, layouts.components(input));
  SmallVector<Type> results;
  for (Type result : label.type.getResults())
    llvm::append_range(results, layouts.components(result));
  return FunctionType::get(module.getContext(), inputs, results);
}

// The code is a function value until convert-to-llvm makes it a pointer; the
// cast between the two disappears then (reconcile-unrealized-casts).
Value Runtime::code(OpBuilder &b, Location loc, const Label &label) {
  unsigned id = layouts.labelId(label);
  usedCode.insert(id);
  Value function = func::ConstantOp::create(b, loc, codeType(label), codeName(id));
  return UnrealizedConversionCastOp::create(b, loc, ptrType(b.getContext()), function)
      .getResult(0);
}

// Loads the captures from the closure, then calls the label's function with
// them before the arguments.
void Runtime::emitCode() {
  OpBuilder b(module.getContext());
  b.setInsertionPointToEnd(module.getBody());
  for (unsigned id : usedCode) {
    const Label &label = layouts.label(id);
    const Cell &cell = layouts.closure(label);
    auto callee = symbols.lookupSymbolIn<func::FuncOp>(module, label.callee);
    Location loc = callee.getLoc();
    FunctionType type = codeType(label);
    auto fn = func::FuncOp::create(b, loc, codeName(id), type);
    symbols.getSymbolTable(module).insert(fn);
    fn.setPrivate();
    OpBuilder::InsertionGuard guard(b);
    Block *entry = fn.addEntryBlock();
    b.setInsertionPointToStart(entry);
    // The closure keeps its captures, and the function takes each owned:
    // one more reference each.
    SmallVector<Value> args;
    for (auto [capture, captureType] : llvm::zip_equal(ArrayRef(cell.fields).drop_front(),
                                                       label.captureTypes())) {
      SmallVector<Value> components = load(b, loc, entry->getArgument(0), capture);
      inc(b, loc, components, layouts.counted(captureType));
      llvm::append_range(args, components);
    }
    llvm::append_range(args, entry->getArguments().drop_front());
    auto result = func::CallOp::create(b, loc, callee, args);
    func::ReturnOp::create(b, loc, result.getResults());
  }
}

} // namespace idr::lower
