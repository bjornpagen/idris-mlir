// quantities-kept: no pass drops or widens a quantity Idris proved. A
// quantity is a type's (idr::quantityOf), so every parameter carries one; a
// parameter or constructor field the emitted module declared keeps the
// quantity it had there. A parameter is known by
// its location: the parser gives each the position of its name in the file,
// and passes copy locations with what they copy, so a parameter that was
// renamed, cloned or moved is still found.

#include "Expect/Expect.h"

#include "mlir/IR/Location.h"
#include "mlir/Parser/Parser.h"

#include <map>

using namespace mlir;

namespace idr::expect {
namespace {

constexpr StringRef property = "quantities-kept";

// The position in a .mlir file that `loc` is, under any names; a location
// made by inlining or folding is another's, and has none.
std::optional<std::pair<unsigned, unsigned>> position(Location loc) {
  while (auto named = dyn_cast<NameLoc>(loc))
    loc = named.getChildLoc();
  auto file = dyn_cast<FileLineColLoc>(loc);
  if (!file || !file.getFilename().getValue().ends_with(".mlir"))
    return std::nullopt;
  return std::make_pair(file.getLine(), file.getColumn());
}

// Whether `block`'s arguments carry quantities Idris proved: a function's
// parameters, and the fields a match's region binds (its default region's
// scrutinee too). A loop's iteration state (scf.while) does not: its
// arguments are the pass's, and the custom syntax drops their locations,
// so a dump read back gives them the dump's own positions.
bool bindsProved(Block &block) {
  Operation *parent = block.getParentOp();
  return isa<func::FuncOp, MatchOp, MatchLitOp>(parent);
}

StringRef spelled(Quantity q) {
  switch (q) {
  case Quantity::Zero:
    return "0";
  case Quantity::One:
    return "1";
  case Quantity::Many:
    return "w";
  }
  return "w";
}

SmallVector<Quantity> fieldQuantities(CtorOp ctor) {
  SmallVector<Quantity> out;
  for (Type type : ctor.getFieldTypes().getAsValueRange<TypeAttr>())
    out.push_back(quantityOf(type));
  return out;
}

} // namespace

LogicalResult quantitiesKept(ModuleOp module, StringRef emitted) {
  if (emitted.empty())
    return fail(module.getLoc(), property) << "name the emitted module, as quantities-kept=<file>";
  OwningOpRef<ModuleOp> reference = parseSourceFile<ModuleOp>(emitted, module.getContext());
  if (!reference)
    return fail(module.getLoc(), property) << "cannot read " << emitted;

  // Every block argument: a parameter, or a field a match's region binds.
  std::map<std::pair<unsigned, unsigned>, Quantity> proved;
  reference->walk([&](Block *block) {
    for (BlockArgument arg : block->getArguments())
      if (auto at = position(arg.getLoc()))
        proved[*at] = quantityOf(arg.getType());
  });
  llvm::StringMap<SmallVector<Quantity>> fields;
  reference->walk([&](CtorOp ctor) {
    fields[(ctor->getParentOfType<DataOp>().getSymName() + "::@" + ctor.getSymName()).str()] =
        fieldQuantities(ctor);
  });

  bool held = true;
  module.walk([&](Block *block) {
    if (!bindsProved(*block))
      return;
    Operation *parent = block->getParentOp();
    auto fn = dyn_cast<func::FuncOp>(parent);
    if (!fn)
      fn = parent->getParentOfType<func::FuncOp>();
    for (BlockArgument arg : block->getArguments()) {
      Quantity now = quantityOf(arg.getType());
      auto at = position(arg.getLoc());
      auto was = at ? proved.find(*at) : proved.end();
      if (was != proved.end() && was->second != now) {
        fail(arg.getLoc(), property)
            << (parent == fn ? "parameter " : "bound field ") << arg.getArgNumber() << " of "
            << where(fn) << " has quantity " << spelled(now) << ", and Idris proved "
            << spelled(was->second);
        held = false;
      }
    }
  });
  module.walk([&](CtorOp ctor) {
    std::string name =
        (ctor->getParentOfType<DataOp>().getSymName() + "::@" + ctor.getSymName()).str();
    auto was = fields.find(name);
    if (was != fields.end() && was->second != fieldQuantities(ctor)) {
      fail(ctor.getLoc(), property) << "the fields of @" << name << " have other quantities than Idris proved";
      held = false;
    }
  });
  return success(held);
}

} // namespace idr::expect
