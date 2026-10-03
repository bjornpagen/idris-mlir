// idr.lower:staticData: the constants idr-lower writes as globals of the
// module, each written once: strings, bigs outside the small range, boxes,
// closures and the messages of crashes; and the code of closures, which
// static closures and new ones alike point to. Runtime's, unexported.
module;
// The runtime's C ABI: a string's and a big's static form is its cells',
// and the runtime itself reads a literal's text.
#include "idris_rt.h"

export module idr.lower:staticData;

import idr.mlir;
import idr.dialect;
import idr.layout;

import :words;

using namespace mlir;

namespace idr::lower {

class StaticData {
public:
  StaticData(ModuleOp m, layout::Layouts &l) : module(m), layouts(l) {}

  // The module's symbols, looked up once per name: idr-lower asks for them
  // per op, and a module can hold many thousands.
  SymbolTableCollection &symbolTables() { return symbols; }

  // Whether a lowered component is static data, which holds no count: the
  // address of a global, or a constant word.
  static bool isStatic(Value component) {
    Operation *def = component.getDefiningOp();
    return def && (isa<LLVM::AddressOfOp>(def) || def->hasTrait<OpTrait::ConstantLike>());
  }

  // The address of the bytes of `text`, written once however many crashes
  // report it.
  Value message(OpBuilder &b, Location loc, StringRef text) {
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
    return addressOf(b, loc, message);
  }

  // The components of the constant `value` of type `type`:
  // scalars as LLVM constants, strings, bigs outside the small range, boxes
  // and closures as static data. Usable in code and in the initializer of a
  // global.
  SmallVector<Value> constant(OpBuilder &b, Location loc, Attribute value, Type type) {
    // A linear value is the value itself at runtime.
    if (isErased(type) || isWorld(type))
      return {};
    type = unrestricted(type);
    if (auto text = dyn_cast<StringAttr>(value))
      return {string(b, loc, text.getValue())};
    if (auto number = dyn_cast<BigAttr>(value))
      return {big(b, loc, number)};
    if (isa<IntegerAttr, FloatAttr>(value))
      return {LLVM::ConstantOp::create(b, loc, type, cast<TypedAttr>(value))};
    if (auto data = dyn_cast<DataType>(type)) {
      auto con = cast<ConAttr>(value);
      const layout::SumLayout &layout = layouts.sum(data.getName().getAttr());
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
                      : layout.counted[slot] ? nullComponent(b, loc, layout.slots[slot])
                                             : LLVM::PoisonOp::create(b, loc, layout.slots[slot]).getResult());
      return out;
    }
    auto key = std::make_pair(value, type);
    auto it = statics.find(key);
    if (it == statics.end()) {
      LLVM::GlobalOp cellGlobal;
      if (auto con = dyn_cast<ConAttr>(value)) {
        auto ctor = symbols.lookupSymbolIn<CtorOp>(module, con.getCtor());
        const layout::Cell &cell = layouts.box(ctor);
        cellGlobal = staticCell(b, loc, "__idr_box_", cell, [&](OpBuilder &init, unsigned i) {
          return constant(init, loc, con.getFields()[i], ctor.getFieldType(i));
        });
      } else {
        auto closure = cast<ClosureAttr>(value);
        const layout::Label &label = layouts.label(layouts.labelId(
            closure.getCallee(), static_cast<unsigned>(closure.getCaptures().size())));
        const layout::Cell &cell = layouts.closure(label);
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

  // The type of the code of `label`'s closures: a function taking the
  // closure, then the arguments.
  FunctionType codeType(const layout::Label &label) {
    SmallVector<Type> inputs{ptrType(module.getContext())};
    for (Type input : label.argumentTypes())
      llvm::append_range(inputs, layouts.components(input));
    SmallVector<Type> results;
    for (Type result : label.type.getResults())
      llvm::append_range(results, layouts.components(result));
    return FunctionType::get(module.getContext(), inputs, results);
  }

  // The address of that code. The code is a function value until
  // convert-to-llvm makes it a pointer; the cast between the two disappears
  // then (reconcile-unrealized-casts).
  Value code(OpBuilder &b, Location loc, const layout::Label &label) {
    unsigned id = layouts.labelId(label);
    usedCode.insert(id);
    Value function = func::ConstantOp::create(b, loc, codeType(label), layout::codeName(id));
    return UnrealizedConversionCastOp::create(b, loc, ptrType(b.getContext()), function)
        .getResult(0);
  }

  // The labels whose code some closure points to, in the order first met.
  ArrayRef<unsigned> usedLabels() const { return usedCode.getArrayRef(); }

private:
  LLVM::GlobalOp global(OpBuilder &b, Location loc, StringRef prefix, Type type,
                        function_ref<Value(OpBuilder &)> init) {
    OpBuilder::InsertionGuard guard(b);
    b.setInsertionPointToStart(module.getBody());
    std::string name = (prefix + Twine(globals++)).str();
    auto global = LLVM::GlobalOp::create(b, loc, type, /*isConstant=*/true, LLVM::Linkage::Private,
                                         name, Attribute(), /*alignment=*/IDRIS_RT_WORD_BYTES);
    b.createBlock(&global.getInitializerRegion());
    LLVM::ReturnOp::create(b, loc, init(b));
    return global;
  }

  Value addressOf(OpBuilder &b, Location loc, LLVM::GlobalOp global) {
    return LLVM::AddressOfOp::create(b, loc, global);
  }

  Value pack(OpBuilder &b, Location loc, Type structType, ValueRange members) {
    Value value = LLVM::PoisonOp::create(b, loc, structType);
    for (auto [i, member] : llvm::enumerate(members))
      value = LLVM::InsertValueOp::create(b, loc, value, member, static_cast<int64_t>(i));
    return value;
  }

  // A cell as static data, count 0: its header, then the components of
  // each field in the cell's address order.
  LLVM::GlobalOp staticCell(OpBuilder &b, Location loc, StringRef prefix, const layout::Cell &cell,
                            function_ref<SmallVector<Value>(OpBuilder &, unsigned field)> components) {
    // A packed struct with the padding as bytes of its own, so that LLVM puts
    // each component at the offset the layout chose, whatever data layout the
    // translation is given.
    MLIRContext *ctx = b.getContext();
    auto i32 = b.getI32Type();
    SmallVector<Type> members{i32, i32};
    // For each member, the component it holds, or none for padding.
    SmallVector<std::optional<std::pair<unsigned, unsigned>>> holds{std::nullopt, std::nullopt};
    unsigned at = sizeof(idris_rt_header);
    auto padTo = [&](unsigned offset) {
      if (offset > at) {
        members.push_back(LLVM::LLVMArrayType::get(b.getI8Type(), offset - at));
        holds.push_back(std::nullopt);
      }
      at = offset;
    };
    for (auto [field, component] : cell.order) {
      const layout::Slot &slot = cell.fields[field][component];
      padTo(slot.offset);
      members.push_back(slot.type);
      holds.push_back(std::make_pair(field, component));
      at += layouts.sizeOf(slot.type);
    }
    padTo(cell.size);
    auto structType = LLVM::LLVMStructType::getLiteral(ctx, members, /*isPacked=*/true);
    return global(b, loc, prefix, structType, [&](OpBuilder &init) -> Value {
      SmallVector<SmallVector<Value>> fields;
      for (unsigned field = 0; field < cell.fields.size(); ++field)
        fields.push_back(components(init, field));
      SmallVector<Value> values{i32Constant(init, loc, 0), i32Constant(init, loc, cell.info.word())};
      for (auto [type, held] : llvm::drop_begin(llvm::zip_equal(members, holds), 2))
        values.push_back(held ? fields[held->first][held->second]
                              : LLVM::ZeroOp::create(init, loc, type).getResult());
      return pack(init, loc, structType, values);
    });
  }

  // A string: the header (count 0: static data), the byte length and the
  // scalar count, which the runtime computes, then the bytes.
  Value string(OpBuilder &b, Location loc, StringRef bytes) {
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
      uint32_t info = layout::CellInfo::string(ascii).word();
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
  // static idris_rt_bignum, its limbs in the same global.
  Value big(OpBuilder &b, Location loc, BigAttr value) {
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
      int64_t size = number->size;
      auto count = static_cast<size_t>(size < 0 ? -size : size);
      SmallVector<int64_t> limbs;
      const auto *digitsOf = reinterpret_cast<const uint64_t *>(number + 1);
      for (size_t i = 0; i < count; ++i)
        limbs.push_back(static_cast<int64_t>(digitsOf[i]));
      idris_rt_big_release(word);
      auto i32 = b.getI32Type();
      auto i64 = b.getI64Type();
      auto limbsType = LLVM::LLVMArrayType::get(i64, count);
      auto type = LLVM::LLVMStructType::getLiteral(b.getContext(), {i32, i32, i64, limbsType});
      auto global = this->global(b, loc, "__idr_big_", type, [&](OpBuilder &init) -> Value {
        Value limbsValue = LLVM::ConstantOp::create(
            init, loc, limbsType,
            DenseElementsAttr::get(
                RankedTensorType::get({static_cast<int64_t>(count)}, init.getI64Type()),
                ArrayRef<int64_t>(limbs)));
        return pack(init, loc, type,
                    {i32Constant(init, loc, 0), i32Constant(init, loc, layout::CellInfo::bignum().word()),
                     i64Constant(init, loc, size), limbsValue});
      });
      it = statics.try_emplace(key, global).first;
    }
    return LLVM::PtrToIntOp::create(b, loc, b.getI64Type(), addressOf(b, loc, it->second));
  }

  ModuleOp module;
  layout::Layouts &layouts;
  unsigned globals = 0;
  DenseMap<std::pair<Attribute, Type>, LLVM::GlobalOp> statics;
  llvm::StringMap<LLVM::GlobalOp> messages;
  llvm::SetVector<unsigned> usedCode;
  SymbolTableCollection symbols;
};

} // namespace idr::lower
