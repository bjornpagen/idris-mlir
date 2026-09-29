// idr-check-profile: the heap-free profile on the optimized module. It
// rejects only what would allocate at runtime:
//   - a box built from a runtime value;
//   - a closure of arguments built at runtime (one that idr-defunctionalize
//     could not turn into a sum);
//   - the same for a closure of no arguments (Lazy, Inf);
//   - such a closure that flows into a function whose specialization
//     stopped (idr.spec_stopped);
//   - a string built at runtime that is passed on or stored instead of being
//     written or used to build another string;
//   - a string primitive other than output applied to a string built at
//     runtime, reported at that primitive;
//   - an Integer computed at runtime.
// Constants of any size are static data. Values that are only passed along
// (fields, match results, call results) are judged where they are built.
//
// The first violation in op order is reported as `unsupported (<reason>)` at
// the innermost user location of the op's call-site chain, with
// the library location in parentheses and the callers as notes. The pass
// then fails; isProfileRejection() recognizes the error.

#include "idr/Idr.h"
#include "idr/Passes.h"

#include "mlir/IR/Matchers.h"
#include "mlir/IR/SymbolTable.h"

#include "llvm/Support/FormatVariadic.h"

using namespace mlir;

namespace idr {
#define GEN_PASS_DEF_IDRCHECKPROFILE
#include "idr/Passes.h.inc"
} // namespace idr

namespace {

struct Violation {
  StringRef reason;
  std::string what;
};

// Ops whose results pass values on without building them.
bool isMove(Operation *op) {
  return isa<idr::FieldOp, idr::MatchOp, idr::MatchLitOp, func::CallOp, idr::ApplyOp,
             scf::WhileOp>(op);
}

// Ops that pass their operands on, or store them.
bool isPassing(Operation *op) {
  return isa<func::CallOp, idr::ApplyOp, func::ReturnOp, idr::YieldOp, idr::ConOp,
             idr::ClosureOp, scf::ConditionOp, scf::YieldOp>(op);
}

// Whether `op` computes a new value of type T.
template <typename T> bool isBuilt(Operation *op) {
  return !op->hasTrait<OpTrait::ConstantLike>() && !isMove(op) &&
         llvm::any_of(op->getResultTypes(), llvm::IsaPred<T>);
}

// An operand that a box or closure can hold as static data.
bool isStatic(Value value) { return matchPattern(value, m_Constant()); }

std::string opName(Operation *op) { return op->getName().getStringRef().str(); }

struct Checker {
  explicit Checker(ModuleOp root) : module(root), users(tables, root) {}

  ModuleOp module;
  SymbolTableCollection tables;
  SymbolUserMap users;

  func::FuncOp callee(func::CallOp call) {
    return tables.lookupNearestSymbolFrom<func::FuncOp>(call, call.getCalleeAttr());
  }

  // Whether the closure built by `closure` reaches a call of a
  // function whose specialization stopped, through calls, returns, matches and
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
          if (fn->hasAttr("idr.spec_stopped"))
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

  // A closure built inside a stopped function counts too: its self tail
  // call may be a loop by now. The function is named by its
  // origin, the one the user wrote.
  std::optional<StringRef> stoppedAt(Operation *closure) {
    auto fn = closure->getParentOfType<func::FuncOp>();
    std::optional<StringRef> stopped;
    if (fn && fn->hasAttr("idr.spec_stopped"))
      stopped = fn.getSymName();
    else
      stopped = reachesStoppedCallee(closure);
    if (!stopped)
      return std::nullopt;
    auto origin = tables.lookupSymbolIn(module, StringAttr::get(module.getContext(), *stopped))
                      ->getAttrOfType<StringAttr>("idr.origin");
    return origin ? origin.getValue() : *stopped;
  }

  std::optional<Violation> closure(idr::ClosureOp op) {
    if (llvm::all_of(op->getOperands(), isStatic))
      return std::nullopt;
    StringRef label = op.getCallee();
    if (std::optional<StringRef> stopped = stoppedAt(op))
      return Violation{"growing specialization",
                       ("function value grows: a closure of @" + label + " is built in or passed to @" +
                        *stopped + ", whose specialization stopped")
                           .str()};
    if (cast<idr::FnType>(op.getType()).getInputs().empty())
      return Violation{"runtime lazy value",
                       ("Lazy value built at runtime: a suspension of @" + label +
                        " whose captures are not known at compile time")
                           .str()};
    return Violation{"runtime closure",
                     ("function value built at runtime: a closure of @" + label +
                      " that no finite choice of functions stands for")
                         .str()};
  }

  // A string passed on, at the op that builds it, or a string primitive
  // applied to one.
  std::optional<Violation> builtString(Operation *op) {
    for (Operation *user : op->getUsers()) {
      if (isa<idr::PutStrOp>(user) || isBuilt<idr::StrType>(user))
        continue;
      if (isPassing(user))
        return Violation{"runtime string",
                         "string built at runtime: the result of " + opName(op) + " is passed to " +
                             opName(user) + " instead of being written by output"};
    }
    return std::nullopt;
  }

  std::optional<Violation> stringPrimitive(Operation *op) {
    for (Value operand : op->getOperands()) {
      Operation *def = operand.getDefiningOp();
      if (isa<idr::StrType>(operand.getType()) && def && isBuilt<idr::StrType>(def))
        return Violation{"string primitive",
                         opName(op) + " of a string built at runtime by " + opName(def)};
    }
    return std::nullopt;
  }

  std::optional<Violation> check(Operation *op) {
    if (auto con = dyn_cast<idr::ConOp>(op)) {
      if (isa<idr::BoxType>(con.getType()) && !llvm::all_of(op->getOperands(), isStatic))
        return Violation{"runtime data", ("recursive data built at runtime: " +
                                          con.getCtor().getLeafReference().getValue() +
                                          " has a field that is not known at compile time")
                                             .str()};
      return std::nullopt;
    }
    if (auto closureOp = dyn_cast<idr::ClosureOp>(op))
      return closure(closureOp);
    if (isBuilt<idr::StrType>(op))
      if (std::optional<Violation> v = builtString(op))
        return v;
    if (!isa<idr::PutStrOp, idr::IncOp, idr::DecOp>(op) && !isBuilt<idr::StrType>(op) &&
        !isPassing(op))
      if (std::optional<Violation> v = stringPrimitive(op))
        return v;
    if (isBuilt<idr::BigType>(op))
      return Violation{"runtime integer",
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

// The error is reported at the innermost user frame.
void report(Operation *op, const Violation &violation) {
  SmallVector<Location> chain;
  frames(op->getLoc(), chain);
  auto user = llvm::find_if(chain, [](Location loc) { return !isLibrary(loc); });
  if (user == chain.end())
    user = chain.begin();
  InFlightDiagnostic diag = emitError(*user) << "unsupported (" << violation.reason
                                             << "): " << violation.what;
  if (user != chain.begin())
    diag << " (in " << position(chain.front()) << ")";
  for (Location caller : llvm::make_range(std::next(user), chain.end()))
    diag.attachNote(caller) << "called from here";
}

struct CheckProfile : idr::impl::IdrCheckProfileBase<CheckProfile> {
  void runOnOperation() override {
    Checker checker(getOperation());
    WalkResult result = getOperation()->walk<WalkOrder::PreOrder>([&](Operation *op) {
      ++numChecked;
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
