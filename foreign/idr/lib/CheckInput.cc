// idr-check-input: the module respects the contract (IDR-MOD-1, IDR-IN-*,
// IDR-DATA-4, IDR-WORLD-1). A failure is an internal error (DIAG-ICE-1): the
// Idris side emitted text outside the contract.

#include "idr/Idr.h"

#include "llvm/ADT/DenseSet.h"
#include "llvm/ADT/SmallPtrSet.h"

using namespace mlir;

namespace idr {
#define GEN_PASS_DEF_IDRCHECKINPUT
#include "idr/Passes.h.inc"
} // namespace idr

namespace {

bool allowedType(Type type) {
  if (auto integer = dyn_cast<IntegerType>(type))
    return integer.isSignless() &&
           llvm::is_contained({1u, 8u, 16u, 32u, 64u}, integer.getWidth());
  return isa<Float64Type, idr::DataType, idr::ErasedType, idr::StrType, idr::WorldType>(type);
}

bool isV1Op(Operation *op) {
  return isa<idr::ToCharOp, idr::StrLitOp, idr::PutStrOp, idr::PutCharOp,
             idr::PutIntOp, idr::GetCharOp, idr::ExitOp>(op);
}

// IDR-DBL-*: Double values, operations and printing.
bool isV2Op(Operation *op) {
  if (isa<idr::ToIntOp, idr::PutDoubleOp>(op) ||
      isa<math::MathDialect>(op->getDialect()))
    return true;
  auto isF64 = [](Type type) { return isa<Float64Type>(type); };
  return llvm::any_of(op->getOperandTypes(), isF64) ||
         llvm::any_of(op->getResultTypes(), isF64);
}

// IDR-IN-1
bool allowedOp(Operation *op) {
  if (isa<idr::IdrDialect>(op->getDialect()))
    return true;
  return isa<ModuleOp, func::FuncOp, func::CallOp, func::ReturnOp,
             arith::ConstantOp, arith::AddIOp, arith::SubIOp, arith::MulIOp,
             arith::AndIOp, arith::OrIOp, arith::XOrIOp, arith::CmpIOp,
             arith::ExtSIOp, arith::ExtUIOp, arith::TruncIOp, cf::BranchOp,
             cf::CondBranchOp, cf::SwitchOp, arith::AddFOp, arith::SubFOp,
             arith::MulFOp, arith::DivFOp, arith::NegFOp, arith::CmpFOp,
             arith::SIToFPOp, arith::UIToFPOp, math::ExpOp, math::LogOp,
             math::PowFOp, math::SinOp, math::CosOp, math::TanOp, math::AsinOp,
             math::AcosOp, math::AtanOp, math::SqrtOp, math::FloorOp,
             math::CeilOp>(op);
}

// IDR-IN-2: arith and math carry no overflow, exact or fast-math flags.
bool hasArithFlags(Operation *op) {
  if (auto flags = op->getAttrOfType<arith::IntegerOverflowFlagsAttr>("overflowFlags"))
    return flags.getValue() != arith::IntegerOverflowFlags::none;
  if (auto flags = op->getAttrOfType<arith::FastMathFlagsAttr>("fastmath"))
    return flags.getValue() != arith::FastMathFlags::none;
  return op->hasAttr("isExact");
}

// The block of `region` that holds `op`, directly or through nested ops.
Block *blockIn(Operation *op, Region *region) {
  while (op && op->getParentRegion() != region)
    op = op->getParentOp();
  return op ? op->getBlock() : nullptr;
}

struct CheckInput : idr::impl::IdrCheckInputBase<CheckInput> {
  void runOnOperation() override {
    ModuleOp module = getOperation();
    bool ok = true;
    auto fail = [&](Operation *op, const Twine &message) {
      op->emitError("idr contract violation: ") << message;
      ok = false;
    };

    // IDR-MOD-1
    auto version = module->getAttrOfType<IntegerAttr>("idr.version");
    if (!version || version.getInt() < 0 || version.getInt() > 3) {
      fail(module, "idr.version must be 0, 1, 2 or 3");
      return signalPassFailure();
    }
    int64_t contract = version.getInt();
    auto entry = module->getAttrOfType<FlatSymbolRefAttr>("idr.entry");
    auto kind = module->getAttrOfType<StringAttr>("idr.entry_kind");
    auto root = entry ? module.lookupSymbol<func::FuncOp>(entry.getAttr())
                      : func::FuncOp();
    if (!root)
      fail(module, "idr.entry must name a func.func");
    else if (!kind || (kind.getValue() != "int" && kind.getValue() != "io"))
      fail(module, "idr.entry_kind must be \"int\" or \"io\"");
    else if (kind.getValue() == "int") {
      auto type = root.getFunctionType();
      if (type.getNumInputs() != 0 || type.getNumResults() != 1 ||
          !type.getResult(0).isInteger(64))
        fail(root, "an int entry has type () -> i64");
    } else {
      auto type = root.getFunctionType();
      if (contract < 1 || type.getNumInputs() != 1 ||
          !isa<idr::WorldType>(type.getInput(0)) || type.getNumResults() != 1)
        fail(root, "an io entry has type (!idr.world) -> T, from version 1");
    }

    // LOW-ENTRY-1: idr-lower creates the C entry point @main.
    if (Operation *reserved = module.lookupSymbol("main"))
      fail(reserved, "the symbol @main is reserved for the C entry point (LOW-ENTRY-1)");

    module.walk([&](Operation *op) {
      if (!allowedOp(op))
        return fail(op, "operation not allowed in the input");
      if (contract < 1 && isV1Op(op))
        fail(op, "operation needs idr.version 1");
      if (contract < 2 && isV2Op(op))
        fail(op, "operation needs idr.version 2");
      if (contract < 3 && isa<idr::CrashOp, idr::DoubleHeadOp, idr::GetByteOp>(op))
        fail(op, "operation needs idr.version 3");
      if (hasArithFlags(op))
        fail(op, "arith flags are not allowed");
      for (Type type : op->getResultTypes())
        if (!allowedType(type))
          fail(op, "result type not allowed");
      for (Region &region : op->getRegions())
        for (Block &block : region)
          for (BlockArgument arg : block.getArguments())
            if (!allowedType(arg.getType()))
              fail(op, "argument type not allowed");
      if (auto fn = dyn_cast<func::FuncOp>(op)) {
        if (!fn.isPrivate())
          fail(fn, "functions must be private (IDR-FN-2)");
        if (fn.getNumResults() == 0)
          fail(fn, "functions have at least one result (IDR-FN-1)");
        for (unsigned i = 0; i < fn.getNumArguments(); ++i) {
          auto q = fn.getArgAttrOfType<StringAttr>(i, "idr.quantity");
          if (!q || !llvm::is_contained({"0", "1", "w"}, q.getValue()))
            fail(fn, "every argument needs idr.quantity (IDR-FN-1)");
        }
      }
      if (isa<idr::DataOp, idr::CtorOp, func::FuncOp>(op) &&
          !op->hasAttr("idr.name"))
        fail(op, "missing idr.name (IDR-DATA-5)");
      // IDR-WORLD-1
      for (Value result : op->getResults())
        if (isa<idr::WorldType>(result.getType()))
          checkWorld(result, fail);
      for (Region &region : op->getRegions())
        for (Block &block : region)
          for (BlockArgument arg : block.getArguments())
            if (isa<idr::WorldType>(arg.getType()))
              checkWorld(arg, fail);
    });

    // IDR-DATA-4: runtime containment is acyclic.
    DenseMap<StringAttr, SmallVector<StringAttr>> edges;
    for (auto data : module.getOps<idr::DataOp>())
      for (auto ctor : data.getCtors())
        for (Attribute field : ctor.getFieldTypes())
          if (auto inner = dyn_cast<idr::DataType>(cast<TypeAttr>(field).getValue())) {
            if (!idr::lookupData(module, inner))
              fail(ctor, "field refers to an undeclared data type");
            edges[data.getSymNameAttr()].push_back(inner.getName().getAttr());
          }
    DenseMap<StringAttr, int> state; // 1 = on stack, 2 = done
    std::function<bool(StringAttr)> acyclic = [&](StringAttr node) {
      int &s = state[node];
      if (s == 1)
        return false;
      if (s == 2)
        return true;
      s = 1;
      for (StringAttr next : edges.lookup(node))
        if (!acyclic(next))
          return false;
      state[node] = 2;
      return true;
    };
    for (auto data : module.getOps<idr::DataOp>())
      if (!acyclic(data.getSymNameAttr()))
        fail(data, "data types are recursive (IDR-DATA-4)");

    if (!ok)
      signalPassFailure();
  }

  // IDR-WORLD-1: a world is used at most once on each path. A use is
  // followed on its path by the rest of its block and by every block
  // reachable from there without passing the world's definition, which
  // defines a new world on each entry.
  template <typename Fail> void checkWorld(Value world, Fail &fail) {
    Region *home = world.getParentRegion();
    Block *def = world.getParentBlock();
    DenseMap<Block *, SmallVector<Operation *>> byBlock;
    for (OpOperand &use : world.getUses()) {
      Block *block = blockIn(use.getOwner(), home);
      if (!block)
        return fail(use.getOwner(), "a world value is used outside its region (IDR-WORLD-1)");
      byBlock[block].push_back(blockIn(use.getOwner(), home) == use.getOwner()->getBlock()
                                   ? use.getOwner()
                                   : use.getOwner()->getParentOp());
    }
    for (auto &[block, users] : byBlock) {
      llvm::SmallPtrSet<Operation *, 4> distinct(users.begin(), users.end());
      if (distinct.size() > 1)
        return fail(users.back(), "a world value is used twice on one path (IDR-WORLD-1)");
      SmallVector<Block *> work(block->getSuccessors().begin(), block->getSuccessors().end());
      llvm::SmallPtrSet<Block *, 16> seen;
      while (!work.empty()) {
        Block *next = work.pop_back_val();
        if (next == def || !seen.insert(next).second)
          continue;
        if (byBlock.count(next))
          return fail(byBlock[next].front(), "a world value is used twice on one path (IDR-WORLD-1)");
        work.append(next->getSuccessors().begin(), next->getSuccessors().end());
      }
    }
  }
};

} // namespace
