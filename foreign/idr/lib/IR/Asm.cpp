// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// How the dialect reads in text: the names the printer gives the results
// of its ops and the arguments of a match's cases, and the aliases of its
// data types and of its large constants. A name or an alias that comes
// from a symbol is that symbol's characters, shortened for the reader by
// one helper; nothing is decided from them. Every hook builds its name in a
// buffer of its own and keeps nothing: the printer runs them from any
// thread an instrumentation prints on.

#include "idr/IR/IdrDialect.h"

#include "mlir/IR/OpImplementation.h"
#include "llvm/ADT/SmallString.h"
#include "llvm/ADT/Twine.h"
#include "llvm/Support/raw_ostream.h"

using namespace mlir;
using namespace idr;

namespace {

// `symbol` shortened for the reader: split at brackets, commas and spaces,
// each piece's text after its last dot, joined with `_`.
// `Prelude.Types.List[Prelude.Types.Nat]` is `List_Nat`, and
// `Data.Vect.Vect[3, Prelude.Types.Nat]` is `Vect_3_Nat`. The characters are
// read only to be shown shorter: what a symbol is, is its declaration's.
void shortName(StringRef symbol, raw_ostream &os) {
  bool first = true;
  while (!symbol.empty()) {
    size_t end = symbol.find_first_of("[], ");
    StringRef piece = symbol.take_front(end);
    symbol = end == StringRef::npos ? StringRef() : symbol.drop_front(end + 1);
    size_t dot = piece.rfind('.');
    if (dot != StringRef::npos)
      piece = piece.drop_front(dot + 1);
    if (piece.empty())
      continue;
    if (!first)
      os << '_';
    os << piece;
    first = false;
  }
}

// A constructor or closure constant with more than this many constructors
// and closures in its tree is printed as an alias. Smaller ones are printed
// in place, as tests read them.
constexpr unsigned aliasFrom = 256;

// Whether `value` has more than `budget` constructors and closures, counted
// as a tree, in at most `budget` steps however much of it is shared. A run
// is one constructor per cell, counted along its cells and then its tail:
// its fields along the spine would rebuild the rest of the run at each cell.
bool larger(Attribute value, unsigned &budget) {
  // One constructor or closure, then its parts.
  auto node = [&](ArrayAttr parts) {
    if (budget == 0)
      return true;
    --budget;
    return llvm::any_of(parts, [&](Attribute part) { return larger(part, budget); });
  };
  if (auto con = dyn_cast<ConAttr>(value)) {
    if (!con.isRun())
      return node(con.getFields());
    for (ArrayAttr cell : con.getRunCells())
      if (node(cell))
        return true;
    return larger(con.getTail(), budget);
  }
  if (auto closure = dyn_cast<ClosureAttr>(value))
    return node(closure.getCaptures());
  return false;
}

// A data type is written by its short name, defined once at the top of
// the text: the symbol itself is as long as the instance it names. A
// constant whose parts are shared has the size of its distinct parts in
// memory, where attributes are uniqued, but a text that spells each part
// out wherever it occurs is the size of its tree, exponentially larger: a
// large one is written once, by name.
struct IdrAsmInterface : OpAsmDialectInterface {
  using OpAsmDialectInterface::OpAsmDialectInterface;

  AliasResult getAlias(Type type, raw_ostream &os) const override {
    FlatSymbolRefAttr name;
    if (auto data = dyn_cast<DataType>(type))
      name = data.getName();
    else if (auto box = dyn_cast<BoxType>(type))
      name = box.getName();
    if (!name)
      return AliasResult::NoAlias;
    SmallString<32> alias;
    llvm::raw_svector_ostream out(alias);
    shortName(name.getValue(), out);
    if (alias.empty())
      return AliasResult::NoAlias;
    os << alias;
    return AliasResult::FinalAlias;
  }

  AliasResult getAlias(Attribute attr, raw_ostream &os) const override {
    unsigned budget = aliasFrom;
    if (!larger(attr, budget))
      return AliasResult::NoAlias;
    os << "idr_value";
    return AliasResult::OverridableAlias;
  }
};

// The leaf of a constructor reference in lower case: `@List::@Nil` is `nil`.
std::string ctorName(SymbolRefAttr ctor) { return ctor.getLeafReference().getValue().lower(); }

} // namespace

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
  setNameFn(getResult(), ctorName(getCtor()));
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

void LambdaOp::getAsmResultNames(OpAsmSetValueNameFn setNameFn) {
  setNameFn(getResult(), "lam");
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
