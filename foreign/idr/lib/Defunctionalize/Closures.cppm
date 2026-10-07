// idr.defunctionalize:closures: the module's closures, gathered once: the
// closure ops and constants of each label, the applies, and the functions
// that escape.
export module idr.defunctionalize:closures;

import idr.mlir;
import idr.dialect;

using namespace mlir;
using namespace mlir::dataflow;

namespace idr::defunctionalize {

// The sum a value of `type`, at any grade, belongs to.
StringAttr dataName(Type type) {
  FlatSymbolRefAttr name = idr::getSumName(type);
  return name ? name.getAttr() : StringAttr();
}

// Whether a slot of `type` holds a closure: a closure, or a linear one,
// whose linearity the pass keeps on everything it rewrites.
bool isClosureType(Type type) { return isa<idr::FnType>(idr::unrestricted(type)); }

struct Module {
  explicit Module(ModuleOp top) : op(top), symbols(top) {}

  ModuleOp op;
  SymbolTable symbols;
  // The closure ops and closure constants (their captures) of each label.
  llvm::DenseMap<StringAttr, SmallVector<idr::ClosureOp>> closures;
  llvm::DenseMap<StringAttr, SmallVector<ArrayAttr>> constantClosures;
  // Suspensions name a function the way a closure does, but the cell is not
  // a sum: the captures still flow into the function, and the function is
  // not a label an apply may call.
  llvm::DenseMap<StringAttr, SmallVector<idr::SuspendOp>> suspends;
  llvm::DenseMap<StringAttr, SmallVector<ArrayAttr>> suspendConstants;
  SmallVector<idr::ApplyOp> applies;
  // Functions referenced other than by a call, closure or constant.
  llvm::DenseSet<StringAttr> escaping;
  // holdsClosure's answers, by constructor constant.
  llvm::DenseMap<Attribute, bool> closureFree;

  idr::CtorOp ctor(StringAttr data, StringAttr name) {
    auto decl = symbols.lookup<idr::DataOp>(data);
    return decl ? decl.lookupSymbol<idr::CtorOp>(name) : idr::CtorOp();
  }

  func::FuncOp function(StringAttr name) { return symbols.lookup<func::FuncOp>(name); }

  // The type of field `index` of `ctor`, whose ref is `@T::@C`.
  Type fieldType(SymbolRefAttr ref, unsigned index) {
    idr::CtorOp decl = ctor(ref.getRootReference(), ref.getLeafReference());
    return decl ? decl.getFieldType(index) : Type();
  }

  // Whether a closure is inside the constant `attr`. Constants of
  // compile-time evaluation share their parts, so a tree may have far more
  // paths than distinct parts: each part is looked at once, and the walks
  // below skip a part with no closure in it.
  bool holdsClosure(Attribute attr) {
    if (isa<idr::ClosureAttr>(attr))
      return true;
    auto con = dyn_cast<idr::ConAttr>(attr);
    if (!con)
      return false;
    auto [it, inserted] = closureFree.try_emplace(attr, false);
    if (!inserted)
      return it->second;
    bool holds = llvm::any_of(con.getFields(), [&](Attribute field) { return holdsClosure(field); });
    closureFree[attr] = holds;
    return holds;
  }

  // Calls `visit(closure, type)` for each closure attribute inside `attr`, a
  // constant of type `type`.
  void closuresIn(Attribute attr, Type type,
                  function_ref<void(idr::ClosureAttr, Type)> visit) {
    if (!holdsClosure(attr))
      return;
    if (auto closure = dyn_cast<idr::ClosureAttr>(attr)) {
      visit(closure, type);
      func::FuncOp fn = function(closure.getCallee().getAttr());
      for (auto [i, capture] : llvm::enumerate(closure.getCaptures()))
        if (fn && i < fn.getNumArguments())
          closuresIn(capture, fn.getArgumentTypes()[i], visit);
      return;
    }
    if (auto con = dyn_cast<idr::ConAttr>(attr))
      for (auto [i, field] : llvm::enumerate(con.getFields()))
        if (Type declared = fieldType(con.getCtor(), static_cast<unsigned>(i)))
          closuresIn(field, declared, visit);
  }

  void gather() {
    op.walk([&](Operation *inner) {
      if (auto closure = dyn_cast<idr::ClosureOp>(inner))
        closures[closure.getCalleeAttr().getAttr()].push_back(closure);
      else if (auto suspend = dyn_cast<idr::SuspendOp>(inner))
        suspends[suspend.getCalleeAttr().getAttr()].push_back(suspend);
      else if (auto apply = dyn_cast<idr::ApplyOp>(inner))
        applies.push_back(apply);
      else if (auto constant = dyn_cast<idr::ConstantOp>(inner))
        closuresIn(constant.getValue(), constant.getType(), [&](idr::ClosureAttr c, Type type) {
          auto &into = isa<idr::LazyType>(idr::unrestricted(type)) ? suspendConstants
                                                                  : constantClosures;
          into[c.getCallee().getAttr()].push_back(c.getCaptures());
        });
    });
    if (std::optional<SymbolTable::UseRange> uses = SymbolTable::getSymbolUses(op.getOperation()))
      for (const SymbolTable::SymbolUse &use : *uses)
        // A clone names itself (idr.clone); no closure escapes there. A
        // suspension names its function the way a closure does.
        if (!isa<func::CallOp, func::FuncOp, idr::ClosureOp, idr::SuspendOp, idr::ConstantOp,
                 idr::ConOp, idr::FieldOp, idr::MatchOp>(use.getUser()))
          escaping.insert(use.getSymbolRef().getRootReference());
  }
};

} // namespace idr::defunctionalize
