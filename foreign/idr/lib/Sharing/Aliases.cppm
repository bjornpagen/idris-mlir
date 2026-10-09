// idr.sharing:aliases: in text, a large constant gets an alias, which the
// printer defines once and refers to by name. (Compile-time evaluation
// sends its results to the compiler as a flat table of their parts, not as
// text.)
export module idr.sharing:aliases;

import idr.mlir;
import idr.dialect;

using namespace mlir;
using namespace idr;

namespace {

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

export namespace idr::sharing {

// Registers the aliases of the dialect's large constants.
void addSharingInterfaces(IdrDialect &dialect) { dialect.addInterfaces<IdrAsm>(); }

} // namespace idr::sharing
