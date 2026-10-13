// The zones of passes and analyses: one pass instrumentation, on the
// manager of idris-mlir and of idris-mlir-opt, which every nested and
// dynamic pipeline run under it (the round's, the inliner's, a module
// pass's own) inherits, so every pass and every analysis gets its zone here
// and no pass adds one for its run.
//
// A zone opened in a before-hook closes in the matching after-hook, a call
// later, so no scope can hold it. MLIR calls a pass's or analysis's
// before- and after-hooks on the one thread that runs it, and Tracy needs
// a zone begun and ended on one thread, so the context Tracy returns is
// kept in this instrumentation, under its mutex, keyed by what the after-
// hook is called with: the pass and the operation it runs on, or the
// analysis's TypeID and its operation. Those pairs are unique among the
// zones open at once: a pass instance runs on one operation at a time,
// and an analysis is not computed on an operation while it is being
// computed there. Tracy's per-thread queue is Tracy's; nothing of ours is
// per thread or atomic.
//
// The names are only known at run time, so each zone's source location is
// allocated, by Tracy, which copies the names and frees the location
// itself. With TRACY_ON_DEMAND a hook does nothing but ask whether a
// capture is connected until one is.

#include "idr/Support/Profile.h"

#ifdef TRACY_ENABLE

#include "mlir/IR/BuiltinAttributes.h"
#include "mlir/IR/Operation.h"
#include "mlir/IR/SymbolTable.h"
#include "mlir/Pass/Pass.h"
#include "mlir/Pass/PassInstrumentation.h"
#include "mlir/Pass/PassManager.h"
#include "mlir/Support/TypeID.h"

#include "llvm/ADT/DenseMap.h"
#include "llvm/ADT/SmallString.h"
#include "llvm/ADT/StringRef.h"

#include <algorithm>
#include <cstddef>
#include <cstdint>
#include <memory>
#include <mutex>
#include <source_location>
#include <utility>

#include "tracy/TracyC.h"

namespace {

using idr::profile::Subsystem;

// A begun zone, as Tracy's C API returns it: by value, inactive when no
// capture was connected as it began.
using Zone = TracyCZoneCtx;

// Begins a zone named `name` whose source location's function is
// `function`; the location's file and line are this file's, where the
// hook is.
Zone beginZone(llvm::StringRef function, llvm::StringRef name, Subsystem subsystem,
               std::source_location where = std::source_location::current()) {
  llvm::StringRef file = where.file_name();
  std::uint64_t location =
      ___tracy_alloc_srcloc_name(where.line(), file.data(), file.size(), function.data(), function.size(),
                                 name.data(), name.size(), idr::profile::color(subsystem));
  // Tracy frees the location when the zone does not begin.
  return ___tracy_emit_zone_begin_alloc(location, 1);
}

// What a pass zone ran on, as its text: the operation's name and, for a
// symbol, its name, which tells one function's run of a function pass
// from another's.
void describe(Zone zone, mlir::Operation *op) {
  llvm::SmallString<128> text(op->getName().getStringRef());
  if (auto symbol = op->getAttrOfType<mlir::StringAttr>(mlir::SymbolTable::getSymbolAttrName())) {
    text += " @";
    text += symbol.getValue();
  }
  // Tracy takes a text shorter than 64 KiB.
  std::size_t size = std::min<std::size_t>(text.size(), 0xFFFE);
  ___tracy_emit_zone_text(zone, text.data(), size);
}

class Zones final : public mlir::PassInstrumentation {
public:
  void runBeforePass(mlir::Pass *pass, mlir::Operation *op) override {
    if (!___tracy_connected())
      return;
    // The name is the one -mlir-timing prints; the function is what a
    // pipeline spells, where the pass has an argument.
    llvm::StringRef name = pass->getName();
    llvm::StringRef argument = pass->getArgument();
    Zone zone = beginZone(argument.empty() ? name : argument, name, Subsystem::Pass);
    if (!zone.active)
      return;
    describe(zone, op);
    std::lock_guard<std::mutex> lock(mutex);
    passes[{pass, op}] = zone;
  }

  void runAfterPass(mlir::Pass *pass, mlir::Operation *op) override { endZone(passes, {pass, op}); }

  void runAfterPassFailed(mlir::Pass *pass, mlir::Operation *op) override { endZone(passes, {pass, op}); }

  void runBeforeAnalysis(llvm::StringRef name, mlir::TypeID id, mlir::Operation *op) override {
    if (!___tracy_connected())
      return;
    Zone zone = beginZone(name, name, Subsystem::Analysis);
    if (!zone.active)
      return;
    std::lock_guard<std::mutex> lock(mutex);
    analyses[{id, op}] = zone;
  }

  void runAfterAnalysis(llvm::StringRef, mlir::TypeID id, mlir::Operation *op) override {
    endZone(analyses, {id, op});
  }

private:
  // Ends the zone `key` began, if one did. With no capture connected there
  // is nothing to end: a zone begun under a capture that has since gone
  // stays in the map until its key begins again, and Tracy ignores the end
  // of a zone of an earlier connection.
  template <typename Key>
  void endZone(llvm::DenseMap<Key, Zone> &zones, Key key) {
    if (!___tracy_connected())
      return;
    Zone zone{};
    {
      std::lock_guard<std::mutex> lock(mutex);
      auto found = zones.find(key);
      if (found == zones.end())
        return;
      zone = found->second;
      zones.erase(found);
    }
    ___tracy_emit_zone_end(zone);
  }

  std::mutex mutex;
  llvm::DenseMap<std::pair<mlir::Pass *, mlir::Operation *>, Zone> passes;
  llvm::DenseMap<std::pair<mlir::TypeID, mlir::Operation *>, Zone> analyses;
};

} // namespace

void idr::profile::addInstrumentation(mlir::PassManager &pm) { pm.addInstrumentation(std::make_unique<Zones>()); }

#else

// Without TRACY_ENABLE there is nothing to add, and this build holds no
// symbol of Tracy's.
void idr::profile::addInstrumentation(mlir::PassManager &) {}

#endif
