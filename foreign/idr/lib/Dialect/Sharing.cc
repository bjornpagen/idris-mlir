// Constants whose parts are shared, as the results of compile-time
// evaluation are, have the size of their distinct parts in memory, where
// attributes are uniqued, but a text that spells each part out wherever it
// occurs is the size of their tree, exponentially larger.
//
// - Bytecode writes each distinct attribute once and refers to it by number.
//   An attribute encoded here refers to its parts the same way; one without
//   an encoding would fall back to its text, parts and all.
// - In text, a large constant gets an alias, which the printer defines once
//   and refers to by name.

#include "Dialect/Sharing.h"

#include "mlir/Bytecode/BytecodeImplementation.h"
#include "mlir/IR/OpImplementation.h"

using namespace mlir;

namespace idr {

namespace {

// The first number of each encoding says which attribute follows. The
// numbers are the format, so a new attribute takes a new one.
enum class Code : uint64_t { Con = 0, Closure = 1, Big = 2, Erased = 3 };

struct IdrBytecode : BytecodeDialectInterface {
  using BytecodeDialectInterface::BytecodeDialectInterface;

  Attribute readAttribute(DialectBytecodeReader &reader) const override {
    MLIRContext *ctx = getContext();
    uint64_t code = 0;
    if (failed(reader.readVarInt(code)))
      return {};
    switch (static_cast<Code>(code)) {
    case Code::Con: {
      SymbolRefAttr ctor;
      ArrayAttr fields;
      if (failed(reader.readAttribute(ctor)) || failed(reader.readAttribute(fields)))
        return {};
      return ConAttr::get(ctx, ctor, fields);
    }
    case Code::Closure: {
      FlatSymbolRefAttr callee;
      ArrayAttr captures;
      if (failed(reader.readAttribute(callee)) || failed(reader.readAttribute(captures)))
        return {};
      return ClosureAttr::get(ctx, callee, captures);
    }
    case Code::Big: {
      StringRef digits;
      if (failed(reader.readString(digits)))
        return {};
      return BigAttr::get(ctx, digits);
    }
    case Code::Erased:
      return ErasedAttr::get(ctx);
    }
    reader.emitError() << "unknown idr attribute code " << code;
    return {};
  }

  LogicalResult writeAttribute(Attribute attribute, DialectBytecodeWriter &writer) const override {
    // Only the untyped form has an encoding; the parser's self type exists
    // only in text (Idr_Attr).
    auto untyped = [](auto attr) { return isa<NoneType>(attr.getType()); };
    if (auto con = dyn_cast<ConAttr>(attribute); con && untyped(con)) {
      writer.writeVarInt(static_cast<uint64_t>(Code::Con));
      writer.writeAttribute(con.getCtor());
      writer.writeAttribute(con.getFields());
      return success();
    }
    if (auto closure = dyn_cast<ClosureAttr>(attribute); closure && untyped(closure)) {
      writer.writeVarInt(static_cast<uint64_t>(Code::Closure));
      writer.writeAttribute(closure.getCallee());
      writer.writeAttribute(closure.getCaptures());
      return success();
    }
    if (auto big = dyn_cast<BigAttr>(attribute); big && untyped(big)) {
      writer.writeVarInt(static_cast<uint64_t>(Code::Big));
      writer.writeOwnedString(big.getValue());
      return success();
    }
    if (auto erased = dyn_cast<ErasedAttr>(attribute); erased && untyped(erased)) {
      writer.writeVarInt(static_cast<uint64_t>(Code::Erased));
      return success();
    }
    return failure();
  }
};

// A constructor or closure constant with more than this many constructors
// and closures in its tree is printed as an alias. Smaller ones are printed
// in place, as tests read them.
constexpr unsigned aliasFrom = 256;

// Whether `value` has more than `budget` constructors and closures, counted
// as a tree, in at most `budget` steps however much of it is shared.
bool larger(Attribute value, unsigned &budget) {
  ArrayAttr parts;
  if (auto con = dyn_cast<ConAttr>(value))
    parts = con.getFields();
  else if (auto closure = dyn_cast<ClosureAttr>(value))
    parts = closure.getCaptures();
  else
    return false;
  if (budget == 0)
    return true;
  --budget;
  for (Attribute part : parts)
    if (larger(part, budget))
      return true;
  return false;
}

struct IdrAsm : OpAsmDialectInterface {
  using OpAsmDialectInterface::OpAsmDialectInterface;

  AliasResult getAlias(Attribute attr, raw_ostream &os) const override {
    unsigned budget = aliasFrom;
    if (!larger(attr, budget))
      return AliasResult::NoAlias;
    os << "idr_value";
    return AliasResult::OverridableAlias;
  }
};

} // namespace

void addSharingInterfaces(IdrDialect &dialect) { dialect.addInterfaces<IdrBytecode, IdrAsm>(); }

} // namespace idr
