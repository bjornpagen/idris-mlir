// quantities-kept: no pass drops or widens a quantity Idris proved. Every
// parameter carries one, and a parameter or constructor field the emitted
// module declared keeps the quantity it had there. A parameter is known by
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

StringAttr quantity(func::FuncOp fn, unsigned index) {
  return fn.getArgAttrOfType<StringAttr>(index, "idr.quantity");
}

} // namespace

LogicalResult quantitiesKept(ModuleOp module, StringRef emitted) {
  if (emitted.empty())
    return fail(module.getLoc(), property) << "name the emitted module, as quantities-kept=<file>";
  OwningOpRef<ModuleOp> reference = parseSourceFile<ModuleOp>(emitted, module.getContext());
  if (!reference)
    return fail(module.getLoc(), property) << "cannot read " << emitted;

  std::map<std::pair<unsigned, unsigned>, StringAttr> proved;
  for (auto fn : reference->getOps<func::FuncOp>())
    if (!fn.isExternal())
      for (BlockArgument arg : fn.getArguments())
        if (auto at = position(arg.getLoc()))
          proved[*at] = quantity(fn, arg.getArgNumber());
  llvm::StringMap<ArrayAttr> fields;
  reference->walk([&](CtorOp ctor) {
    fields[(ctor->getParentOfType<DataOp>().getSymName() + "::" + ctor.getSymName()).str()] =
        ctor.getQuantities();
  });

  bool held = true;
  for (auto fn : module.getOps<func::FuncOp>()) {
    if (fn.isExternal())
      continue;
    for (BlockArgument arg : fn.getArguments()) {
      StringAttr now = quantity(fn, arg.getArgNumber());
      if (!now) {
        fail(arg.getLoc(), property) << "parameter " << arg.getArgNumber() << " of "
                                     << where(fn) << " has no quantity";
        held = false;
        continue;
      }
      auto at = position(arg.getLoc());
      auto was = at ? proved.find(*at) : proved.end();
      if (was != proved.end() && was->second && was->second != now) {
        fail(arg.getLoc(), property) << "parameter " << arg.getArgNumber() << " of " << where(fn)
                                     << " has quantity " << now.getValue()
                                     << ", and Idris proved " << was->second.getValue();
        held = false;
      }
    }
  }
  module.walk([&](CtorOp ctor) {
    std::string name =
        (ctor->getParentOfType<DataOp>().getSymName() + "::" + ctor.getSymName()).str();
    auto was = fields.find(name);
    if (was != fields.end() && was->second != ctor.getQuantities()) {
      fail(ctor.getLoc(), property) << "the fields of @" << name << " have other quantities than Idris proved";
      held = false;
    }
  });
  return success(held);
}

} // namespace idr::expect
