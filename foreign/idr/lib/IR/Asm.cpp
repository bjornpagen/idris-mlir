// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// How the dialect reads in text: a constructor written by its name and read
// back into its tag, the names the printer gives the results of its ops and
// the arguments of a match's cases, and the aliases of its data types and
// of its large constants. A name or an alias that comes from a symbol is
// that symbol's characters, shortened for the reader by one helper; nothing
// is decided from them. Every hook builds its name in a buffer of its own
// and keeps nothing: the printer runs them from any thread an
// instrumentation prints on.

#include "idr/IR/IdrDialect.h"
#include "idr/IR/Symbols.h"

#include "mlir/IR/OpImplementation.h"
#include "llvm/ADT/SmallString.h"
#include "llvm/ADT/StringExtras.h"
#include "llvm/ADT/Twine.h"
#include "llvm/Support/raw_ostream.h"

#include <functional>
#include <optional>

using namespace mlir;
using namespace idr;

namespace {

// `symbol` shortened for the reader: split at brackets, commas and spaces,
// each piece's text after its last dot, joined with `_`.
// `Prelude.Types.List[Prelude.Types.Nat]` is `List_Nat`, and
// `Data.Vect.Vect[3, Prelude.Types.Nat]` is `Vect_3_Nat`. The characters are
// read only to be shown shorter: what a symbol is, is its declaration's.
void shortName(StringRef symbol, raw_ostream &os) {
  SmallVector<StringRef> pieces;
  llvm::SplitString(symbol, pieces, "[], ");
  bool first = true;
  for (StringRef piece : pieces) {
    StringRef last = piece.rsplit('.').second;
    StringRef shown = piece.contains('.') ? last : piece;
    if (shown.empty())
      continue;
    if (!first)
      os << '_';
    os << shown;
    first = false;
  }
}

// A constructor or closure constant with more than this many constructors
// and closures in its tree is printed as an alias. Smaller ones are printed
// in place, as tests read them. A size policy of the printer's: it bounds
// the text, never what is printed.
constexpr unsigned aliasFrom = 256;

// The number of constructors and closures in `value`, counted as a tree,
// or `cap` if there are at least that many: at most `cap` of them are
// visited however much of it is shared, and each step reads a part of the
// one before, so the walk ends with the attribute. A run is one constructor
// per cell, counted along its cells and then its tail: its fields along the
// spine would rebuild the rest of the run at each cell.
unsigned treeSize(Attribute value, unsigned cap) {
  // `counted` so far, then what each of `parts` adds, up to the cap.
  auto add = [cap](unsigned counted, ArrayRef<Attribute> parts) {
    for (Attribute part : parts)
      if (counted < cap)
        counted += treeSize(part, cap - counted);
    return counted;
  };
  if (cap == 0)
    return 0;
  if (auto closure = dyn_cast<ClosureAttr>(value))
    return add(1, closure.getCaptures().getValue());
  auto con = dyn_cast<ConAttr>(value);
  if (!con)
    return 0;
  if (!con.isRun())
    return add(1, con.getFields().getValue());
  unsigned counted = 0;
  for (ArrayAttr cell : con.getRunCells())
    if (counted < cap)
      counted = add(counted + 1, cell.getValue());
  return add(counted, con.getTail());
}

// A data type is written by its short name, defined once at the top of
// the text with its body: its name is as long as the instance it names,
// and its body would be spelled out wherever it occurs. A box is its data
// type's alias in a box. A constant whose parts are shared has the size of
// its distinct parts in memory, where attributes are uniqued, but a text
// that spells each part out wherever it occurs is the size of its tree,
// exponentially larger: a large one is written once, by name.
struct IdrAsmInterface : OpAsmDialectInterface {
  using OpAsmDialectInterface::OpAsmDialectInterface;

  AliasResult getAlias(Type type, raw_ostream &os) const override {
    auto data = dyn_cast<DataType>(type);
    if (!data)
      return AliasResult::NoAlias;
    SmallString<32> alias;
    llvm::raw_svector_ostream out(alias);
    shortName(data.getName(), out);
    if (alias.empty())
      return AliasResult::NoAlias;
    os << alias;
    return AliasResult::FinalAlias;
  }

  AliasResult getAlias(Attribute attr, raw_ostream &os) const override {
    if (treeSize(attr, aliasFrom + 1) <= aliasFrom)
      return AliasResult::NoAlias;
    os << "idr_value";
    return AliasResult::OverridableAlias;
  }
};

// The constructor `tag` of the data type of `type`, or nothing where the
// printer meets an op the verifier would reject.
std::optional<std::reference_wrapper<const Ctor>> ctorOf(Type type, int64_t tag) {
  DataType data = dataTypeOf(type);
  if (!data || tag < 0 || static_cast<uint64_t>(tag) >= data.getCtors().size())
    return std::nullopt;
  return data.getCtor(Tag{static_cast<uint32_t>(tag)});
}

// A constructor's name in lower case: `@Nil` is `nil`.
std::string ctorName(const Ctor &ctor) { return ctor.name.getValue().lower(); }

} // namespace

//===----------------------------------------------------------------------===//
// A constructor by its name
//===----------------------------------------------------------------------===//

ParseResult idr::parseCtorRef(AsmParser &parser, Type type, IntegerAttr &tag) {
  SMLoc loc = parser.getCurrentLocation();
  StringAttr name;
  if (parser.parseSymbolName(name))
    return failure();
  DataType data = dataTypeOf(type);
  if (!data)
    return parser.emitError(loc) << "expects a constructor of a data type, not of " << type;
  std::optional<Tag> found = data.getTag(name.getValue());
  if (!found)
    return parser.emitError(loc) << "the data type \"" << data.getName()
                                 << "\" has no constructor @" << name.getValue();
  tag = parser.getBuilder().getI32IntegerAttr(static_cast<int32_t>(*found));
  return success();
}

// A tag the type has no constructor of is printed as a number, which no
// parser reads back: only an op the verifier rejects holds one.
void idr::printCtorRef(OpAsmPrinter &printer, Operation *, Type type, IntegerAttr tag) {
  std::optional<std::reference_wrapper<const Ctor>> ctor =
      tag ? ctorOf(type, tag.getInt()) : std::nullopt;
  if (ctor)
    printer.printSymbolName(ctor->get().name.getValue());
  else
    printer << "<<no constructor " << tag << ">>";
}

void idr::detail::addAsmInterface(IdrDialect &dialect) {
  dialect.addInterfaces<IdrAsmInterface>();
}

void ConstantOp::getAsmResultNames(OpAsmSetValueNameFn setNameFn) {
  Type carrier = unrestricted(getType());
  Attribute value = getValue();
  if (isa<StringAttr>(value))
    setNameFn(getResult(), "str");
  else if (isa<BigAttr>(value))
    setNameFn(getResult(), isa<NatType>(carrier) ? "nat" : "big");
  else if (isa<ClosureAttr>(value))
    setNameFn(getResult(), isa<LazyType>(carrier) ? "thunk" : "clo");
  else if (auto con = dyn_cast<ConAttr>(value))
    setNameFn(getResult(), ctorName(con.getCtor()));
}

void ConOp::getAsmResultNames(OpAsmSetValueNameFn setNameFn) {
  if (std::optional<std::reference_wrapper<const Ctor>> ctor =
          ctorOf(getResult().getType(), static_cast<int64_t>(getTag())))
    setNameFn(getResult(), ctorName(*ctor));
}

void ClosureOp::getAsmResultNames(OpAsmSetValueNameFn setNameFn) {
  setNameFn(getResult(), "clo");
}

void SuspendOp::getAsmResultNames(OpAsmSetValueNameFn setNameFn) {
  setNameFn(getResult(), "thunk");
}

void DelayOp::getAsmResultNames(OpAsmSetValueNameFn setNameFn) {
  setNameFn(getResult(), "thunk");
}

void LinEnterOp::getAsmResultNames(OpAsmSetValueNameFn setNameFn) {
  setNameFn(getResult(), "lin");
}

void ForceOp::getAsmResultNames(OpAsmSetValueNameFn setNameFn) {
  setNameFn(getResult(), "forced");
}

void ApplyOp::getAsmResultNames(OpAsmSetValueNameFn setNameFn) {
  for (Value result : getResults())
    setNameFn(result, "applied");
}

// The callee's short name before its instance's arguments, in lower case:
// a call of `Prelude.Show.show[Prelude.Types.Nat]` is `%show`.
void CallOp::getAsmResultNames(OpAsmSetValueNameFn setNameFn) {
  SmallString<32> name;
  llvm::raw_svector_ostream os(name);
  shortName(getCallee().split('[').first, os);
  if (name.empty())
    return;
  std::string lower = StringRef(name).lower();
  for (Value result : getResults())
    setNameFn(result, lower);
}

// A case binds its constructor's fields, in order; the default binds
// nothing of its own. A field's Idris name is its argument's location,
// which the printer reads when asked to.
void MatchOp::getAsmBlockArgumentNames(Region &region, OpAsmSetValueNameFn setNameFn) {
  if (&region == getDefaultRegion())
    return;
  for (BlockArgument arg : region.getArguments()) {
    SmallString<8> name;
    ("f" + Twine(arg.getArgNumber())).toVector(name);
    setNameFn(arg, name);
  }
}
