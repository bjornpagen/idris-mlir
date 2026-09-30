// Constants whose parts are shared, as the results of compile-time
// evaluation are, have the size of their distinct parts in memory, where
// attributes are uniqued, but a text that spells each part out wherever it
// occurs is the size of their tree, exponentially larger. In text, a large
// constant gets an alias, which the printer defines once and refers to by
// name. (Compile-time evaluation sends its results to the compiler as a
// flat table of their parts, Eval/Reify.h, not as text.)

#include "Dialect/Sharing.h"

#include "mlir/IR/OpImplementation.h"

using namespace mlir;

namespace idr {

namespace {

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

void addSharingInterfaces(IdrDialect &dialect) { dialect.addInterfaces<IdrAsm>(); }

} // namespace idr
