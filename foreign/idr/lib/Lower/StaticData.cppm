// idr.lower:staticData: the constants idr-lower writes as globals of the
// module, each written once: strings, bigs outside the small range, boxes,
// among them the memo cells of constant thunks, and the messages of
// crashes; and @__idr_release_cafs, which releases what those memo cells
// hold. Runtime's, unexported.
module;
// The runtime's C ABI: a string's and a big's static form is its cells',
// the runtime itself reads a literal's text, and a cell's kind is its info
// word's, as the runtime reads it.
#include "idris_rt.h"

export module idr.lower:staticData;

import idr.mlir;
import idr.dialect;
import idr.fold;
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
      message = global(b, loc, "__idr_msg_", type, /*isConstant=*/true, [&](OpBuilder &init) -> Value {
        return LLVM::ConstantOp::create(init, loc, type, init.getStringAttr(text));
      });
      messages[text] = message;
    }
    return addressOf(b, loc, message);
  }

  // The components of the constant `value` of type `type`:
  // scalars as LLVM constants, strings, bigs outside the small range and
  // boxes as static data. Usable in code and in the initializer of a
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
    auto con = cast<ConAttr>(value);
    if (auto data = dyn_cast<DataType>(type))
      return unboxed(b, loc, con, data);
    return {addressOf(b, loc, box(b, loc, con, type))};
  }

  // @__idr_release_cafs, which the program's entry calls when the program
  // ends: idris_rt_caf_release on each static memo cell, which releases
  // what its first force stored there. A module without one has it too,
  // empty, so that the entry calls it without asking. Built once, after the
  // last constant is lowered.
  void emitReleaseCafs(OpBuilder &b) {
    OpBuilder::InsertionGuard guard(b);
    b.setInsertionPointToEnd(module.getBody());
    Location loc = module.getLoc();
    auto release = func::FuncOp::create(b, loc, "__idr_release_cafs", b.getFunctionType({}, {}));
    release.setPrivate();
    symbols.getSymbolTable(module).insert(release);
    b.setInsertionPointToStart(release.addEntryBlock());
    for (LLVM::GlobalOp cell : cafs)
      LLVM::CallOp::create(b, loc, cafRelease(b), addressOf(b, loc, cell));
    func::ReturnOp::create(b, loc);
  }

private:
  // An unboxed sum: its tag, then its slots.
  SmallVector<Value> unboxed(OpBuilder &b, Location loc, ConAttr con, DataType data) {
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
    // A slot the constructor does not use holds zero: empty where the slot
    // is counted, so that counting the sum counts each of its slots.
    for (auto [slot, component] : llvm::enumerate(slots))
      out.push_back(component ? component : LLVM::ZeroOp::create(b, loc, layout.slots[slot]).getResult());
    return out;
  }

  // The global of the box `con` of type `type`, written once however many
  // constants hold it.
  LLVM::GlobalOp box(OpBuilder &b, Location loc, ConAttr con, Type type) {
    auto key = std::make_pair(Attribute(con), type);
    if (auto it = statics.find(key); it != statics.end())
      return it->second;
    auto ctor = symbols.lookupSymbolIn<CtorOp>(module, con.getCtor());
    LLVM::GlobalOp cellGlobal;
    if (con.isRun()) {
      cellGlobal = run(b, loc, con, ctor);
    } else {
      ArrayAttr fields = con.getFields();
      cellGlobal = staticCell(b, loc, ctor, [&](OpBuilder &init, unsigned i) {
        return constant(init, loc, fields[i], ctor.getFieldType(i));
      });
    }
    statics.try_emplace(key, cellGlobal);
    return cellGlobal;
  }

  // The cells of a run, written from its tail back to its first cell, each
  // pointing at the one written before it: however long the list, the
  // stack holds one cell. The first cell's global.
  LLVM::GlobalOp run(OpBuilder &b, Location loc, ConAttr con, CtorOp ctor) {
    unsigned spine = con.getSpine();
    Type spineType = unrestricted(ctor.getFieldType(spine));
    ArrayRef<ArrayAttr> cells = con.getRunCells();
    LLVM::GlobalOp rest = box(b, loc, cast<ConAttr>(con.getTail()), spineType);
    auto write = [&](ArrayAttr fields) {
      return staticCell(b, loc, ctor, [&](OpBuilder &init, unsigned i) -> SmallVector<Value> {
        if (i == spine)
          return {addressOf(init, loc, rest)};
        // A run's cell holds its fields without the spine.
        return constant(init, loc, fields[i < spine ? i : i - 1], ctor.getFieldType(i));
      });
    };
    // A memo cell is one per value, or a force would run and store the same
    // value twice: a constant that names the run from one of its cells on
    // must find that cell. So each cell after the first (box keeps the
    // first) is kept under the run from it, which costs that run's length to
    // build; only runs of memo labels pay it. A box has no identity to keep,
    // and its run is written straight.
    bool memo = isMemoCell(layouts.box(ctor));
    for (size_t k = cells.size() - 1; k > 0; --k) {
      if (!memo) {
        rest = write(cells[k]);
        continue;
      }
      auto from = ConAttr::getRun(b.getContext(), con.getCtor(), spine, cells.drop_front(k),
                                  con.getTail());
      auto key = std::make_pair(Attribute(from), spineType);
      if (auto it = statics.find(key); it != statics.end()) {
        rest = it->second;
        continue;
      }
      rest = write(cells[k]);
      statics.try_emplace(key, rest);
    }
    return write(cells.front());
  }

  // Whether a force writes a cell of this layout: a memo cell, by its kind.
  static bool isMemoCell(const layout::Cell &cell) {
    return idris_rt_info_kind(cell.info.word()) == IDRIS_RT_KIND_THUNK;
  }

  // idris_rt_caf_release, declared on first use.
  LLVM::LLVMFuncOp cafRelease(OpBuilder &b) {
    StringRef name = "idris_rt_caf_release";
    if (auto declared = symbols.lookupSymbolIn<LLVM::LLVMFuncOp>(module, b.getStringAttr(name)))
      return declared;
    OpBuilder::InsertionGuard guard(b);
    b.setInsertionPointToStart(module.getBody());
    MLIRContext *ctx = b.getContext();
    auto type = LLVM::LLVMFunctionType::get(LLVM::LLVMVoidType::get(ctx), ptrType(ctx));
    auto declared = LLVM::LLVMFuncOp::create(b, module.getLoc(), name, type);
    symbols.getSymbolTable(module).insert(declared);
    return declared;
  }

  LLVM::GlobalOp global(OpBuilder &b, Location loc, StringRef prefix, Type type, bool isConstant,
                        function_ref<Value(OpBuilder &)> init) {
    OpBuilder::InsertionGuard guard(b);
    b.setInsertionPointToStart(module.getBody());
    std::string name = (prefix + Twine(globals++)).str();
    auto global = LLVM::GlobalOp::create(b, loc, type, isConstant, LLVM::Linkage::Private, name,
                                         Attribute(), /*alignment=*/IDRIS_RT_WORD_BYTES);
    b.createBlock(&global.getInitializerRegion());
    LLVM::ReturnOp::create(b, loc, init(b));
    return global;
  }

  Value addressOf(OpBuilder &b, Location loc, LLVM::GlobalOp global) {
    return LLVM::AddressOfOp::create(b, loc, global);
  }

  // A struct of `members`, inserted one by one into the zero struct, which
  // LLVM folds into one constant.
  Value pack(OpBuilder &b, Location loc, Type structType, ValueRange members) {
    Value value = LLVM::ZeroOp::create(b, loc, structType);
    for (auto [i, member] : llvm::enumerate(members))
      value = LLVM::InsertValueOp::create(b, loc, value, member, static_cast<int64_t>(i));
    return value;
  }

  // A box of `ctor` as static data, count 0: its header, then the
  // components of each field in the cell's address order. A memo cell, whose
  // kind says a force writes it, is the one static cell that is not
  // constant, and the release lists it. It is one per process: constant
  // data holds its address (a stream's tail), which a thread-local global's
  // is not at link time.
  LLVM::GlobalOp staticCell(OpBuilder &b, Location loc, CtorOp ctor,
                            function_ref<SmallVector<Value>(OpBuilder &, unsigned field)> components) {
    const layout::Cell &cell = layouts.box(ctor);
    bool memo = isMemoCell(cell);
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
    LLVM::GlobalOp cellGlobal = global(b, loc, memo ? "__idr_caf_" : "__idr_box_", structType,
                                       /*isConstant=*/!memo, [&](OpBuilder &init) -> Value {
      SmallVector<SmallVector<Value>> fields;
      for (unsigned field = 0; field < cell.fields.size(); ++field)
        fields.push_back(components(init, field));
      SmallVector<Value> values{i32Constant(init, loc, 0), i32Constant(init, loc, cell.info.word())};
      for (auto [type, held] : llvm::drop_begin(llvm::zip_equal(members, holds), 2))
        values.push_back(held ? fields[held->first][held->second]
                              : LLVM::ZeroOp::create(init, loc, type).getResult());
      return pack(init, loc, structType, values);
    });
    if (memo)
      cafs.push_back(cellGlobal);
    return cellGlobal;
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
      auto global = this->global(b, loc, "__idr_str_", type, /*isConstant=*/true,
                                 [&](OpBuilder &init) -> Value {
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
  // static idris_rt_bignum, its limbs in the same global. The folders'
  // scope holds what the runtime gives and releases it when this returns,
  // counted as theirs are; the limbs are read before then.
  Value big(OpBuilder &b, Location loc, BigAttr value) {
    fold::Scope scope(b.getContext());
    idris_rt_big word = scope.big(value);
    if ((word & 1) != 0)
      return i64Constant(b, loc, word);
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
      auto i32 = b.getI32Type();
      auto i64 = b.getI64Type();
      auto limbsType = LLVM::LLVMArrayType::get(i64, count);
      auto type = LLVM::LLVMStructType::getLiteral(b.getContext(), {i32, i32, i64, limbsType});
      auto global = this->global(b, loc, "__idr_big_", type, /*isConstant=*/true,
                                 [&](OpBuilder &init) -> Value {
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
  // The static memo cells, in the order they were written.
  SmallVector<LLVM::GlobalOp> cafs;
  SymbolTableCollection symbols;
};

} // namespace idr::lower
