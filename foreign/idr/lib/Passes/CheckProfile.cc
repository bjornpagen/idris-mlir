// idr-check-profile: the heap-free profile on the optimized module
// (docs/cutover.md 3.3). It rejects only what would allocate at runtime:
//   - PROF-DATA-3: a box built from a runtime value;
//   - PROF-HEAP-1: a closure of arguments built at runtime (one that
//     idr-defunctionalize could not turn into a sum);
//   - PROF-HEAP-2: the same for a closure of no arguments (Lazy, Inf);
//   - PROF-HEAP-4: such a closure that flows into a function whose
//     specialization the clone limit stopped (idr.clone_limit_hit);
//   - PROF-HEAP-3: a string built at runtime that is passed on or stored
//     instead of being written or used to build another string;
//   - PROF-PRIM-4: a string primitive other than output applied to a string
//     built at runtime, reported at that primitive;
//   - PROF-TYPE-4: an Integer computed at runtime.
// Constants of any size are static data. Values that are only passed along
// (fields, match results, call results) are judged where they are built.
//
// The first violation in op order is reported as `unsupported (<RULE>)` at
// the innermost user location of the op's call-site chain (DIAG-LOC-1), with
// the library location in parentheses and the callers as notes. The pass
// then fails; isProfileRejection() recognizes the error.

#include "idr/Idr.h"
#include "idr/Passes.h"

#include "mlir/IR/Matchers.h"
#include "mlir/IR/SymbolTable.h"

using namespace mlir;

namespace idr {
#define GEN_PASS_DEF_IDRCHECKPROFILE
#include "idr/Passes.h.inc"
} // namespace idr

namespace {

struct Violation {
  StringRef rule;
  std::string what;
};

// Ops that pass a value on without building one.
bool isMove(Operation *op) {
  return isa<idr::FieldOp, idr::MatchOp, idr::MatchLitOp, func::CallOp, idr::ApplyOp>(op);
}

bool isBuilt(Operation *op, Type type) {
  return !op->hasTrait<OpTrait::ConstantLike>() && !isMove(op) &&
         llvm::any_of(op->getResultTypes(), [&](Type t) { return t == type; });
}

// A value with no runtime content of its own: a constant, or erased.
bool isStatic(Value value) {
  return isa<idr::ErasedType>(value.getType()) || matchPattern(value, m_Constant());
}

std::string opName(Operation *op) { return op->getName().getStringRef().str(); }

struct Checker {
  ModuleOp module;
  SymbolTableCollection tables;
  SymbolUserMap users{tables, module};

  func::FuncOp callee(func::CallOp call) {
    return tables.lookupNearestSymbolFrom<func::FuncOp>(call, call.getCalleeAttr());
  }

  // PROF-HEAP-4: whether the closure built by `closure` reaches a call of a
  // function the clone limit stopped, through calls, returns, matches and
  // the values it is stored in.
  std::optional<StringRef> reachesStoppedCallee(Operation *closure) {
    SmallVector<Value> work{closure->getResult(0)};
    DenseSet<Value> seen;
    while (!work.empty()) {
      Value value = work.pop_back_val();
      if (!seen.insert(value).second)
        continue;
      for (OpOperand &use : value.getUses()) {
        Operation *user = use.getOwner();
        if (auto call = dyn_cast<func::CallOp>(user)) {
          func::FuncOp fn = callee(call);
          if (!fn || fn.isExternal())
            continue;
          if (fn->hasAttr("idr.clone_limit_hit"))
            return fn.getSymName();
          work.push_back(fn.getArgument(use.getOperandNumber()));
        } else if (isa<func::ReturnOp>(user)) {
          auto fn = user->getParentOfType<func::FuncOp>();
          for (Operation *caller : users.getUsers(fn))
            if (isa<func::CallOp>(caller))
              work.push_back(caller->getResult(use.getOperandNumber()));
        } else if (isa<idr::YieldOp>(user)) {
          work.push_back(user->getParentOp()->getResult(use.getOperandNumber()));
        } else if (isa<idr::ConOp, idr::ClosureOp>(user)) {
          work.push_back(user->getResult(0));
        }
      }
    }
    return std::nullopt;
  }

  std::optional<Violation> closure(idr::ClosureOp op) {
    if (llvm::all_of(op->getOperands(), isStatic))
      return std::nullopt;
    StringRef label = op.getCallee();
    if (std::optional<StringRef> stopped = reachesStoppedCallee(op))
      return Violation{"PROF-HEAP-4",
                       ("function value grows: a closure of @" + label + " is passed to @" +
                        *stopped + ", whose specialization stopped at the clone limit")
                           .str()};
    if (cast<idr::FnType>(op.getType()).getInputs().empty())
      return Violation{"PROF-HEAP-2",
                       ("Lazy value built at runtime: a suspension of @" + label +
                        " whose captures are not known at compile time")
                           .str()};
    return Violation{"PROF-HEAP-1",
                     ("function value built at runtime: a closure of @" + label +
                      " that no finite choice of functions stands for")
                         .str()};
  }

  // PROF-HEAP-3 at the op that builds a string, PROF-PRIM-4 at a string
  // primitive applied to one.
  std::optional<Violation> builtString(Operation *op) {
    for (Operation *user : op->getUsers()) {
      if (isa<idr::PutStrOp>(user) || isBuilt(user, op->getResult(0).getType()))
        continue;
      if (isa<func::CallOp, idr::ApplyOp, func::ReturnOp, idr::YieldOp, idr::ConOp,
              idr::ClosureOp>(user))
        return Violation{"PROF-HEAP-3",
                         "string built at runtime: the result of " + opName(op) + " is passed to " +
                             opName(user) + " instead of being written by output"};
    }
    return std::nullopt;
  }

  std::optional<Violation> stringPrimitive(Operation *op) {
    for (Value operand : op->getOperands()) {
      Operation *def = operand.getDefiningOp();
      if (isa<idr::StrType>(operand.getType()) && def && isBuilt(def, operand.getType()))
        return Violation{"PROF-PRIM-4", opName(op) + " of a string built at runtime by " +
                                            opName(def)};
    }
    return std::nullopt;
  }

  std::optional<Violation> check(Operation *op) {
    MLIRContext *ctx = module.getContext();
    if (auto con = dyn_cast<idr::ConOp>(op)) {
      if (isa<idr::BoxType>(con.getType()) && !llvm::all_of(op->getOperands(), isStatic))
        return Violation{"PROF-DATA-3", ("recursive data built at runtime: " +
                                         con.getCtor().getLeafReference().getValue() +
                                         " has a field that is not known at compile time")
                                            .str()};
      return std::nullopt;
    }
    if (auto closureOp = dyn_cast<idr::ClosureOp>(op))
      return closure(closureOp);
    if (isBuilt(op, idr::StrType::get(ctx)))
      if (std::optional<Violation> v = builtString(op))
        return v;
    if (!isa<idr::PutStrOp>(op) && !isBuilt(op, idr::StrType::get(ctx)) &&
        !isa<func::CallOp, idr::ApplyOp, func::ReturnOp, idr::YieldOp, idr::ConOp,
             idr::ClosureOp>(op))
      if (std::optional<Violation> v = stringPrimitive(op))
        return v;
    if (isBuilt(op, idr::BigType::get(ctx)))
      return Violation{"PROF-TYPE-4",
                       "Integer computed at runtime by " + opName(op) + ", which may allocate"};
    return std::nullopt;
  }
};

bool isLibrary(Location loc) {
  if (auto name = dyn_cast<NameLoc>(loc))
    return isLibrary(name.getChildLoc());
  auto fused = dyn_cast<FusedLoc>(loc);
  auto origin = fused ? dyn_cast_or_null<StringAttr>(fused.getMetadata()) : StringAttr();
  return origin && origin.getValue() == "library";
}

// The frames of a call-site chain, innermost first.
void frames(Location loc, SmallVectorImpl<Location> &out) {
  if (auto site = dyn_cast<CallSiteLoc>(loc)) {
    frames(site.getCallee(), out);
    frames(site.getCaller(), out);
    return;
  }
  out.push_back(loc);
}

// `file:line:col` of the first source position in a location.
std::string position(Location loc) {
  std::string out;
  loc->walk([&](Location sub) {
    auto file = dyn_cast<FileLineColLoc>(sub);
    if (!file)
      return WalkResult::advance();
    out = llvm::formatv("{0}:{1}:{2}", file.getFilename().getValue(), file.getLine(),
                        file.getColumn());
    return WalkResult::interrupt();
  });
  if (out.empty())
    llvm::raw_string_ostream(out) << loc;
  return out;
}

// DIAG-LOC-1: the error is reported at the innermost user frame.
void report(Operation *op, const Violation &violation) {
  SmallVector<Location> chain;
  frames(op->getLoc(), chain);
  auto user = llvm::find_if(chain, [](Location loc) { return !isLibrary(loc); });
  if (user == chain.end())
    user = chain.begin();
  InFlightDiagnostic diag = emitError(*user) << "unsupported (" << violation.rule
                                             << "): " << violation.what;
  if (user != chain.begin())
    diag << " (in " << position(chain.front()) << ")";
  for (Location caller : llvm::make_range(std::next(user), chain.end()))
    diag.attachNote(caller) << "called from here";
}

struct CheckProfile : idr::impl::IdrCheckProfileBase<CheckProfile> {
  void runOnOperation() override {
    Checker checker{getOperation()};
    WalkResult result = getOperation()->walk<WalkOrder::PreOrder>([&](Operation *op) {
      std::optional<Violation> violation = checker.check(op);
      if (!violation)
        return WalkResult::advance();
      report(op, *violation);
      return WalkResult::interrupt();
    });
    if (result.wasInterrupted())
      signalPassFailure();
  }
};

} // namespace

bool idr::isProfileRejection(const Diagnostic &diag) {
  return diag.getSeverity() == DiagnosticSeverity::Error &&
         StringRef(diag.str()).starts_with("unsupported (");
}
