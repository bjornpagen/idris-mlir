// The idr dialect: types, attributes, constants, and the rules of the module
// and of its functions.

#include "idr/Idr.h"

#include "Ownership/Ownership.h"

#include "mlir/IR/Builders.h"
#include "mlir/IR/DialectImplementation.h"
#include "mlir/IR/Matchers.h"
#include "mlir/Transforms/InliningUtils.h"
#include "llvm/ADT/DenseSet.h"
#include "llvm/ADT/TypeSwitch.h"

#include <functional>

using namespace mlir;
using namespace idr;

#include "idr/IdrDialect.cc.inc"

#include "idr/IdrEnums.cc.inc"

#define GET_ATTRDEF_CLASSES
#include "idr/IdrAttrs.cc.inc"

#define GET_TYPEDEF_CLASSES
#include "idr/IdrTypes.cc.inc"

namespace {

// Every idr op may be inlined anywhere. (No function body ends in
// ub.unreachable, which the inliner cannot handle: PINS.md:
// inline-unreachable.)
struct IdrInliner : DialectInlinerInterface {
  using DialectInlinerInterface::DialectInlinerInterface;
  bool isLegalToInline(Operation *, Region *, bool, IRMapping &) const final { return true; }
  bool isLegalToInline(Region *, Region *, bool, IRMapping &) const final {
    return true;
  }
};

} // namespace

void IdrDialect::initialize() {
  addTypes<
#define GET_TYPEDEF_LIST
#include "idr/IdrTypes.cc.inc"
      >();
  addAttributes<
#define GET_ATTRDEF_LIST
#include "idr/IdrAttrs.cc.inc"
      >();
  addOperations<
#define GET_OP_LIST
#include "idr/IdrOps.cc.inc"
      >();
  addInterfaces<IdrInliner>();
}

// idr.constant for the dialect's values and strings, and
// arith.constant for scalars.
Operation *IdrDialect::materializeConstant(OpBuilder &builder, Attribute value,
                                           Type type, Location loc) {
  if (ConstantOp::isBuildableWith(value, type))
    return ConstantOp::create(builder, loc, type, value);
  if (arith::ConstantOp::isBuildableWith(value, type))
    return arith::ConstantOp::create(builder, loc, type, cast<TypedAttr>(value));
  return nullptr;
}

//===----------------------------------------------------------------------===//
// Types and attributes
//===----------------------------------------------------------------------===//

FunctionType FnType::getFunctionType() const {
  return FunctionType::get(getContext(), getInputs(), getResults());
}

// `!idr.fn<(A...) -> (R...)>`, with both lists always parenthesized.
Type FnType::parse(AsmParser &parser) {
  SmallVector<Type> inputs, results;
  auto list = [&](SmallVectorImpl<Type> &types) {
    return parser.parseCommaSeparatedList(AsmParser::Delimiter::Paren, [&] {
      return parser.parseType(types.emplace_back());
    });
  };
  if (parser.parseLess() || list(inputs) || parser.parseArrow() || list(results) ||
      parser.parseGreater())
    return {};
  return FnType::get(parser.getContext(), inputs, results);
}

void FnType::print(AsmPrinter &printer) const {
  printer << "<(";
  llvm::interleaveComma(getInputs(), printer);
  printer << ") -> (";
  llvm::interleaveComma(getResults(), printer);
  printer << ")>";
}

// One spelling per integer, so that equal bigs are equal attributes.
LogicalResult BigAttr::verify(function_ref<InFlightDiagnostic()> emitError,
                              StringRef value, Type) {
  StringRef digits = value;
  digits.consume_front("-");
  bool canonical = !digits.empty() && llvm::all_of(digits, llvm::isDigit) &&
                   (digits == "0" ? value == "0" : digits.front() != '0');
  if (!canonical)
    return emitError() << "expects a big in canonical decimal, got \"" << value << "\"";
  return success();
}

LogicalResult ConAttr::verify(function_ref<InFlightDiagnostic()> emitError,
                              SymbolRefAttr ctor, ArrayAttr, Type) {
  if (ctor.getNestedReferences().size() != 1)
    return emitError() << "expects a constructor reference @T::@C, got " << ctor;
  return success();
}

bool idr::isFieldType(Type type) {
  if (auto integer = dyn_cast<IntegerType>(type))
    return integer.isSignless() && llvm::is_contained({8u, 16u, 32u, 64u}, integer.getWidth());
  if (auto lin = dyn_cast<LinType>(type))
    return isFieldType(lin.getValue());
  return isa<Float64Type, DataType, BoxType, FnType, StrType, BigType, WorldType,
             ErasedType>(type);
}

// A linear value of a runtime type: the erased value is never used, and
// the world is linear already.
LogicalResult LinType::verify(function_ref<InFlightDiagnostic()> emitError, Type value) {
  if (isa<LinType, ErasedType, WorldType>(value) || !isFieldType(value))
    return emitError() << "expects !idr.lin of a runtime type other than the world, got " << value;
  return success();
}

idr::Quantity idr::quantityOf(Type type) {
  if (isa<ErasedType>(type))
    return Quantity::Zero;
  return isa<LinType, WorldType>(type) ? Quantity::One : Quantity::Many;
}

Type idr::unrestricted(Type type) {
  auto lin = dyn_cast<LinType>(type);
  return lin ? lin.getValue() : type;
}

//===----------------------------------------------------------------------===//
// Lookup helpers
//===----------------------------------------------------------------------===//

FlatSymbolRefAttr idr::getSumName(Type type) {
  return TypeSwitch<Type, FlatSymbolRefAttr>(type)
      .Case<DataType, BoxType>([](auto sum) { return sum.getName(); })
      .Default([](Type) { return nullptr; });
}

DataOp idr::lookupData(Operation *from, Type type) {
  FlatSymbolRefAttr name = getSumName(type);
  if (!name)
    return nullptr;
  return SymbolTable::lookupNearestSymbolFrom<DataOp>(from, name);
}

CtorOp idr::lookupCtor(DataOp data, StringRef ctor) {
  if (!data)
    return nullptr;
  return dyn_cast_or_null<CtorOp>(SymbolTable::lookupSymbolIn(data, ctor));
}

CtorOp idr::lookupCtor(Operation *from, SymbolRefAttr ctor) {
  if (ctor.getNestedReferences().size() != 1)
    return nullptr;
  auto data = SymbolTable::lookupNearestSymbolFrom<DataOp>(
      from, FlatSymbolRefAttr::get(ctor.getRootReference()));
  return lookupCtor(data, ctor.getLeafReference());
}

//===----------------------------------------------------------------------===//
// The module
//===----------------------------------------------------------------------===//

namespace {

LogicalResult verifyLinearity(FunctionOpInterface fn);

// Runs before the ops inside the module are verified, so it assumes nothing
// that their verifiers check.
LogicalResult verifyProgram(ModuleOp module) {
  // One root, which is the only public function, of one of the two kinds.
  SmallVector<func::FuncOp> roots;
  for (auto fn : module.getOps<func::FuncOp>())
    if (fn.isPublic())
      roots.push_back(fn);
  if (roots.size() != 1)
    return module.emitOpError("expects exactly one public function (the root), found ")
           << roots.size();
  FunctionType root = roots.front().getFunctionType();
  Builder b(module.getContext());
  bool intRoot = root.getInputs().empty() && root.getNumResults() == 1 &&
                 root.getResult(0) == b.getI64Type();
  bool ioRoot = root.getInputs().size() == 1 && isa<WorldType>(root.getInput(0));
  if (!intRoot && !ioRoot)
    return roots.front().emitOpError("is the root, so its type must be () -> i64 or "
                                     "(!idr.world) -> (...), not ")
           << root;

  llvm::DenseMap<StringAttr, DataOp> datas;
  for (auto data : module.getOps<DataOp>())
    datas[data.getSymNameAttr()] = data;

  // Every sum or box type names a declaration of its kind.
  auto checkType = [&](Operation *op, Type type) -> WalkResult {
    auto check = [&](FlatSymbolRefAttr name, bool boxed) -> WalkResult {
      DataOp data = datas.lookup(name.getAttr());
      if (!data) {
        op->emitOpError("uses an undeclared data type ") << name;
        return WalkResult::interrupt();
      }
      if (data.getBox() != boxed) {
        op->emitOpError("uses ") << type << ", but " << name << " is declared "
                                 << (data.getBox() ? "box, so its values are !idr.box"
                                                   : "unboxed, so its values are !idr.data");
        return WalkResult::interrupt();
      }
      return WalkResult::advance();
    };
    if (auto data = dyn_cast<DataType>(type))
      return check(data.getName(), false);
    if (auto box = dyn_cast<BoxType>(type))
      return check(box.getName(), true);
    return WalkResult::advance();
  };
  WalkResult types = module.walk([&](Operation *op) -> WalkResult {
    auto walkType = [&](Type type) { return checkType(op, type); };
    if (op->getAttrDictionary().walk(walkType).wasInterrupted())
      return WalkResult::interrupt();
    for (Type type : op->getResultTypes())
      if (type.walk(walkType).wasInterrupted())
        return WalkResult::interrupt();
    for (Region &region : op->getRegions())
      for (Block &block : region)
        for (Type type : block.getArgumentTypes())
          if (type.walk(walkType).wasInterrupted())
            return WalkResult::interrupt();
    return WalkResult::advance();
  });
  if (types.wasInterrupted())
    return failure();

  // Containment through unboxed sums is acyclic, so
  // every cycle of types passes through a box.
  enum class Mark { Open, Done };
  llvm::DenseMap<DataOp, Mark> marks;
  std::function<LogicalResult(DataOp)> visit = [&](DataOp data) -> LogicalResult {
    if (!data)
      return success();
    auto [it, fresh] = marks.try_emplace(data, Mark::Open);
    if (!fresh && it->second == Mark::Open)
      return data.emitOpError("contains itself through unboxed sums; a recursive "
                              "type must be declared box");
    if (!fresh)
      return success();
    for (auto ctor : data.getBody().getOps<CtorOp>()) {
      ArrayAttr fields = ctor.getFieldTypesAttr();
      for (Attribute field : fields ? fields.getValue() : ArrayRef<Attribute>()) {
        auto type = dyn_cast<TypeAttr>(field);
        auto sum = type ? dyn_cast<DataType>(type.getValue()) : nullptr;
        if (sum && failed(visit(datas.lookup(sum.getName().getAttr()))))
          return failure();
      }
    }
    marks[data] = Mark::Done;
    return success();
  };
  for (auto data : module.getOps<DataOp>())
    if (failed(visit(data)))
      return failure();
  for (auto fn : module.getOps<FunctionOpInterface>())
    if (failed(verifyLinearity(fn)))
      return failure();
  return success();
}

//===----------------------------------------------------------------------===//
// Linearity: worlds and !idr.lin values
//===----------------------------------------------------------------------===//

// Whether each region of `branch` returns straight to it, so that at most
// one runs: the regions of a match or of an scf.if, not those of a loop.
bool exclusiveRegions(RegionBranchOpInterface branch) {
  return llvm::all_of(branch->getRegions(), [&](Region &region) {
    SmallVector<RegionSuccessor> next;
    branch.getSuccessorRegions(region, next);
    return llvm::all_of(next, [](RegionSuccessor &successor) { return successor.isOperation(); });
  });
}

// The uses of one linear value, counted on the worst path. The regions of
// a match, and of any op whose regions exclude each other, are alternative
// paths; a region that may run repeatedly counts twice. A region of several
// blocks, which the contract does not produce, counts every use in it.
class LinearUses {
public:
  explicit LinearUses(Value value) : world(value) {
    Region *home = world.getParentRegion();
    for (OpOperand &use : world.getUses())
      for (Operation *op = use.getOwner(); op; op = op->getParentOp()) {
        if (!holders.insert(op).second)
          break;
        if (op->getParentRegion() == home) {
          top.push_back(op);
          break;
        }
        byBlock[op->getBlock()].push_back(op);
      }
    llvm::DenseMap<Block *, unsigned> order;
    for (Block &block : *home)
      order[&block] = order.size();
    llvm::sort(top, [&](Operation *a, Operation *b) {
      if (a->getBlock() != b->getBlock())
        return order[a->getBlock()] < order[b->getBlock()];
      return a->isBeforeInBlock(b);
    });
  }

  // The first op after which the value has been used twice, if any.
  Operation *secondUse() {
    unsigned total = 0;
    for (Operation *op : top) {
      total += count(op);
      if (total > 1)
        return op;
    }
    return nullptr;
  }

private:
  unsigned count(Region &region) {
    unsigned total = 0;
    for (Block &block : region)
      for (Operation *op : byBlock.lookup(&block))
        total += count(op);
    return total;
  }

  unsigned count(Operation *op) {
    // idr.inc takes a reference of its own to what a cell still holds; the
    // value is not consumed. idr.dec is a consumption like any other.
    unsigned total =
        isa<IncOp>(op) ? 0u : static_cast<unsigned>(llvm::count(op->getOperands(), world));
    if (op->getNumRegions() == 0)
      return total;
    auto branch = dyn_cast<RegionBranchOpInterface>(op);
    bool exclusive = branch && exclusiveRegions(branch);
    unsigned regions = 0;
    for (unsigned index = 0, e = op->getNumRegions(); index < e; ++index) {
      unsigned uses = count(op->getRegion(index));
      if (uses && !exclusive && branch && branch.isRepetitiveRegion(index))
        uses = 2;
      regions = exclusive ? std::max(regions, uses) : regions + uses;
    }
    return total + regions;
  }

  Value world;
  llvm::DenseSet<Operation *> holders;
  SmallVector<Operation *> top;
  llvm::DenseMap<Block *, SmallVector<Operation *>> byBlock;
};

// Every value of quantity 1, a world or an !idr.lin, is used at most once
// on every path. Its types say where it may go; this says how often.
LogicalResult verifyLinearity(FunctionOpInterface fn) {
  auto check = [&](Value value) -> LogicalResult {
    if (quantityOf(value.getType()) != Quantity::One)
      return success();
    if (Operation *op = LinearUses(value).secondUse())
      return op->emitOpError(isa<WorldType>(value.getType())
                                 ? "uses a world that is already used on the same path"
                                 : "uses a linear value that is already used on the same path");
    return success();
  };
  WalkResult result = fn->walk([&](Block *block) -> WalkResult {
    for (BlockArgument arg : block->getArguments())
      if (failed(check(arg)))
        return WalkResult::interrupt();
    for (Operation &op : *block)
      for (Value value : op.getResults())
        if (failed(check(value)))
          return WalkResult::interrupt();
    return WalkResult::advance();
  });
  return failure(result.wasInterrupted());
}

} // namespace

//===----------------------------------------------------------------------===//
// The dialect's attributes on other ops
//===----------------------------------------------------------------------===//

LogicalResult IdrDialect::verifyOperationAttribute(Operation *op, NamedAttribute attr) {
  StringRef key = attr.getName().getValue();
  if (key == "idr.program") {
    if (!isa<ModuleOp>(op) || !isa<UnitAttr>(attr.getValue()))
      return op->emitOpError("expects idr.program as a unit attribute of the module");
    return verifyProgram(cast<ModuleOp>(op));
  }
  // After idr-rc every reference is explicit, and consumed exactly once on
  // every path (lib/Ownership).
  if (key == ownership::stageAttr) {
    auto stage = dyn_cast<StringAttr>(attr.getValue());
    if (!isa<ModuleOp>(op) || !stage || stage.getValue() != ownership::ownedStage)
      return op->emitOpError("expects idr.stage = \"owned\" on the module");
    return ownership::verifyOwned(cast<ModuleOp>(op));
  }
  // The facts of a function (lib/Facts): what Idris proves, whether it was
  // written in a library, and what idr-effects finds.
  if (key == "idr.total" || key == "idr.library") {
    if (!isa<func::FuncOp>(op) || !isa<UnitAttr>(attr.getValue()))
      return op->emitOpError("expects ") << key << " as a unit attribute of a function";
    return success();
  }
  if (key == "idr.effects") {
    if (!isa<func::FuncOp>(op) || !isa<EffectAttr>(attr.getValue()))
      return op->emitOpError("expects idr.effects = #idr.effects<...> on a function");
    return success();
  }
  // idr-stack's mark of a box whose cell never leaves its frame
  // (lib/Stack/Pass.cc).
  if (key == "idr.stack") {
    auto con = dyn_cast<ConOp>(op);
    if (!con || !isa<BoxType>(con.getType()) || !isa<UnitAttr>(attr.getValue()))
      return op->emitOpError("expects idr.stack as a unit attribute of an idr.con of a box");
    return success();
  }
  // What idr-specialize keeps between runs (lib/Passes/Specialize.cc): the
  // clones made of each origin, a clone's origin and patterns, and the calls
  // and callees whose specialization stopped.
  if (key == "idr.clone_counts") {
    auto counts = dyn_cast<DictionaryAttr>(attr.getValue());
    if (!isa<ModuleOp>(op) || !counts ||
        !llvm::all_of(counts.getValue(), [](NamedAttribute entry) {
          return isa<IntegerAttr>(entry.getValue());
        }))
      return op->emitOpError("expects idr.clone_counts as a dictionary of counts on the module");
    return success();
  }
  if (key == "idr.spec_caller" || key == "idr.spec_history") {
    auto history = dyn_cast<DictionaryAttr>(attr.getValue());
    bool on = key == "idr.spec_caller" ? isa<func::CallOp>(op) : isa<func::FuncOp>(op);
    if (!on || !history || !llvm::all_of(history.getValue(), [](NamedAttribute entry) {
          return isa<StringAttr>(entry.getValue());
        }))
      return op->emitOpError("expects ")
             << key << " as a dictionary of key texts on a "
             << (key == "idr.spec_caller" ? "call" : "function");
    return success();
  }
  if (key == "idr.origin") {
    if (!isa<func::FuncOp>(op) || !isa<StringAttr>(attr.getValue()))
      return op->emitOpError("expects idr.origin as a string attribute of a function");
    return success();
  }
  if (key == "idr.spec_key") {
    Attribute value = attr.getValue();
    if (!isa<func::FuncOp>(op) ||
        !isa<SpecKeyAttr, KeyApplyAttr, KeyApplyFieldAttr, KeyWriteAttr, StringAttr>(value))
      return op->emitOpError("expects idr.spec_key as the key of a clone");
    return success();
  }
  if (key == "idr.spec_stopped_at") {
    if (!isa<func::CallOp>(op) || !isa<StringAttr>(attr.getValue()))
      return op->emitOpError("expects idr.spec_stopped_at as a string attribute of a call");
    return success();
  }
  if (key == "idr.spec_stopped") {
    if (!isa<func::FuncOp, func::CallOp>(op) || !isa<UnitAttr>(attr.getValue()))
      return op->emitOpError("expects idr.spec_stopped as a unit attribute of a function or call");
    return success();
  }
  return op->emitOpError("has an unknown idr attribute ") << attr.getName();
}

// A parameter's quantity is its type; the argument attributes are the
// passes' own marks.
LogicalResult IdrDialect::verifyRegionArgAttribute(Operation *op, unsigned,
                                                   unsigned argIndex,
                                                   NamedAttribute attr) {
  auto fn = dyn_cast<FunctionOpInterface>(op);
  // idr-specialize numbers a clone's parameters by the holes of its key.
  if (attr.getName().getValue() == "idr.hole" && fn && isa<IntegerAttr>(attr.getValue()))
    return success();
  // idr-rc's parameters that the function borrows (lib/Ownership).
  if (attr.getName().getValue() == ownership::borrowedAttr && fn) {
    if (!isa<UnitAttr>(attr.getValue()) ||
        !isa<StrType, BigType, BoxType, FnType, DataType>(fn.getArgumentTypes()[argIndex]))
      return op->emitOpError("expects idr.borrowed as a unit attribute of a parameter that "
                             "holds references, not of argument ")
             << argIndex;
    return success();
  }
  return op->emitOpError("has an unknown idr argument attribute ") << attr.getName();
}
