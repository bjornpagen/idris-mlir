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
  return LLVM::ConstantOp::create(b, loc, b.getI32Type(), b.getI32IntegerAttr(value));
}

Value at(OpBuilder &b, Location loc, Value cell, unsigned offset) {
  return LLVM::GEPOp::create(b, loc, ptrType(b.getContext()), b.getI8Type(), cell,
                             ArrayRef<LLVM::GEPArg>{static_cast<int32_t>(offset)});
}

} // namespace

std::string crashMessage(Location loc, StringRef cause) {
  std::string where = describe(loc);
  return ("idris-mlir: " + cause + (where.empty() ? "" : " at " + where) + "\n").str();
}

std::string codeName(unsigned id) { return ("__idr_code_" + Twine(id)).str(); }

Value Runtime::call(OpBuilder &b, Location loc, StringRef name, Type result, ValueRange args) {
  auto callee = module.lookupSymbol<LLVM::LLVMFuncOp>(name);
  if (!callee) {
    OpBuilder::InsertionGuard guard(b);
    b.setInsertionPointToStart(module.getBody());
    Type returns = result ? result : LLVM::LLVMVoidType::get(b.getContext());
    auto type = LLVM::LLVMFunctionType::get(returns, llvm::to_vector(args.getTypes()));
    callee = LLVM::LLVMFuncOp::create(b, module.getLoc(), name, type);
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
}

void Runtime::crashIf(OpBuilder &b, Location loc, Value condition, StringRef cause) {
  auto check = scf::IfOp::create(b, loc, condition, /*withElseRegion=*/false);
  OpBuilder::InsertionGuard guard(b);
  b.setInsertionPointToStart(check.thenBlock());
  crash(b, loc, cause);
}

Value Runtime::allocate(OpBuilder &b, Location loc, unsigned size, uint32_t info) {
  Value cell = call(b, loc, jit ? "idris_rt_arena_alloc" : "idris_rt_cell",
                    ptrType(b.getContext()), i64Constant(b, loc, size));
  LLVM::StoreOp::create(b, loc, i32Constant(b, loc, 1), cell);
  LLVM::StoreOp::create(b, loc, i32Constant(b, loc, info), at(b, loc, cell, 4));
  return cell;
}

void Runtime::store(OpBuilder &b, Location loc, Value cell, ArrayRef<Slot> slots,
                    ValueRange values) {
  for (auto [slot, value] : llvm::zip_equal(slots, values))
    LLVM::StoreOp::create(b, loc, value, at(b, loc, cell, slot.offset));
}

SmallVector<Value> Runtime::load(OpBuilder &b, Location loc, Value cell, ArrayRef<Slot> slots) {
  SmallVector<Value> values;
  for (const Slot &slot : slots)
    values.push_back(LLVM::LoadOp::create(b, loc, slot.type, at(b, loc, cell, slot.offset)));
  return values;
}

Value Runtime::loadInfo(OpBuilder &b, Location loc, Value cell) {
  return LLVM::LoadOp::create(b, loc, b.getI32Type(), at(b, loc, cell, 4));
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

// LOW-STR-2: the header (count 0: static data), the byte length and the
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
    auto global = this->global(b, loc, "__idr_str_", type, [&](OpBuilder &init) -> Value {
      SmallVector<Value> values{i32Constant(init, loc, 0), i32Constant(init, loc, ascii ? 1 : 0),
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

// LOW-BIG-1: the runtime reads the decimal text (one semantics for what a
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
                  {i32Constant(init, loc, 0), i32Constant(init, loc, 0),
                   i32Constant(init, loc, static_cast<int64_t>(count)), i32Constant(init, loc, size),
                   addressOf(init, loc, limbsGlobal)});
    });
    it = statics.try_emplace(key, global).first;
  }
  return LLVM::PtrToIntOp::create(b, loc, b.getI64Type(), addressOf(b, loc, it->second));
}

SmallVector<Value> Runtime::constant(OpBuilder &b, Location loc, Attribute value, Type type) {
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
    CtorOp ctor = lookupCtor(module, con.getCtor());
    SmallVector<Value> slots(layout.slots.size());
    const auto &fields = layout.fields.find(ctor.getSymName())->second;
    for (auto [i, field] : llvm::enumerate(con.getFields()))
      for (auto [slot, component] :
           llvm::zip_equal(fields[i], constant(b, loc, field, ctor.getFieldType(i))))
        slots[slot] = component;
    SmallVector<Value> out;
    if (layout.tag)
      out.push_back(LLVM::ConstantOp::create(b, loc, layout.tag,
                                             b.getIntegerAttr(layout.tag, ctor.getTag())));
    for (auto [slot, component] : llvm::enumerate(slots))
      out.push_back(component ? component
                              : LLVM::PoisonOp::create(b, loc, layout.slots[slot]).getResult());
    return out;
  }
  auto key = std::make_pair(value, type);
  auto it = statics.find(key);
  if (it == statics.end()) {
    LLVM::GlobalOp cellGlobal;
    if (auto con = dyn_cast<ConAttr>(value)) {
      CtorOp ctor = lookupCtor(module, con.getCtor());
      const Cell &cell = layouts.box(ctor);
      auto structType = LLVM::LLVMStructType::getLiteral(b.getContext(), cell.members(b.getContext()));
      cellGlobal = global(b, loc, "__idr_box_", structType, [&](OpBuilder &init) -> Value {
        SmallVector<Value> members{i32Constant(init, loc, 0),
                                   i32Constant(init, loc, static_cast<int64_t>(ctor.getTag()))};
        for (auto [i, field] : llvm::enumerate(con.getFields()))
          llvm::append_range(members, constant(init, loc, field, ctor.getFieldType(i)));
        return pack(init, loc, structType, members);
      });
    } else {
      auto closure = cast<ClosureAttr>(value);
      const Label &label = layouts.label(layouts.labelId(
          closure.getCallee(), static_cast<unsigned>(closure.getCaptures().size())));
      const Cell &cell = layouts.closure(label);
      auto structType = LLVM::LLVMStructType::getLiteral(b.getContext(), cell.members(b.getContext()));
      cellGlobal = global(b, loc, "__idr_closure_", structType, [&](OpBuilder &init) -> Value {
        SmallVector<Value> members{i32Constant(init, loc, 0),
                                   i32Constant(init, loc, layouts.labelId(label)),
                                   code(init, loc, label)};
        for (auto [capture, captureType] :
             llvm::zip_equal(closure.getCaptures(), label.captureTypes()))
          llvm::append_range(members, constant(init, loc, capture, captureType));
        return pack(init, loc, structType, members);
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
  if (!llvm::is_contained(usedCode, id))
    usedCode.push_back(id);
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
    auto callee = module.lookupSymbol<func::FuncOp>(label.callee.getAttr());
    Location loc = callee.getLoc();
    FunctionType type = codeType(label);
    auto fn = func::FuncOp::create(b, loc, codeName(id), type);
    fn.setPrivate();
    OpBuilder::InsertionGuard guard(b);
    Block *entry = fn.addEntryBlock();
    b.setInsertionPointToStart(entry);
    SmallVector<Value> args;
    for (const auto &capture : ArrayRef(cell.fields).drop_front())
      llvm::append_range(args, load(b, loc, entry->getArgument(0), capture));
    llvm::append_range(args, entry->getArguments().drop_front());
    auto result = func::CallOp::create(b, loc, callee, args);
    func::ReturnOp::create(b, loc, result.getResults());
  }
}

} // namespace idr::lower
