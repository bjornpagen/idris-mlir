// The idr dialect: types, attributes, constants, and the rules of the module
// and of its functions.

#include "idr/Idr.h"

#include "Dialect/Sharing.h"
#include "Ownership/Ownership.h"

#include "mlir/IR/Builders.h"
#include "mlir/IR/DialectImplementation.h"
#include "mlir/IR/Matchers.h"
#include "mlir/Transforms/InliningUtils.h"
#include "llvm/ADT/DenseSet.h"
#include "llvm/ADT/TypeSwitch.h"

#include <functional>
#include <string_view>

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
  addSharingInterfaces(*this);
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
  return isa<Float64Type, DataType, BoxType, FnType, StrType, BigType, NatType, WorldType,
             ErasedType>(type);
}

// A linear value of a runtime type: the erased value is never used, and
// the world is linear already.
LogicalResult LinType::verify(function_ref<InFlightDiagnostic()> emitError, Type value) {
  if (isa<LinType, ErasedType, WorldType>(value) || !isFieldType(value))
    return emitError() << "expects !idr.lin of a runtime type other than the world, got " << value;
  return success();
}

// A destination is one word of a cell that a box's reference fills: a
// field of box type.
LogicalResult DestType::verify(function_ref<InFlightDiagnostic()> emitError, Type value) {
  if (!isa<BoxType>(value))
    return emitError() << "expects !idr.dest of a box type, got " << value;
  return success();
}

// A destination is written exactly once, so it is used exactly once.
idr::Quantity idr::quantityOf(Type type) {
  if (isa<ErasedType>(type))
    return Quantity::Zero;
  return isa<LinType, WorldType, DestType>(type) ? Quantity::One : Quantity::Many;
}

Type idr::unrestricted(Type type) {
  auto lin = dyn_cast<LinType>(type);
  return lin ? lin.getValue() : type;
}

Value idr::throughLinear(Value value) {
  for (;;) {
    if (auto enter = value.getDefiningOp<LinEnterOp>()) {
      value = enter.getValue();
      continue;
    }
    auto use = value.getDefiningOp<LinUseOp>();
    auto enter = use ? use.getLinear().getDefiningOp<LinEnterOp>() : LinEnterOp();
    if (!enter)
      return value;
    value = enter.getValue();
  }
}

bool idr::readOnce(Value value) {
  while (value.hasOneUse()) {
    Operation *def = value.getDefiningOp();
    if (!isa_and_nonnull<LinUseOp, LinEnterOp>(def))
      return true;
    value = def->getOperand(0);
  }
  return false;
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

std::optional<idr::Elimination> idr::eliminationAt(OpOperand &use) {
  // The only user of `v`, if it has one.
  auto next = [](Value v) { return v.hasOneUse() ? *v.user_begin() : nullptr; };
  Elimination e;
  Value value = use.get();
  Operation *user = use.getOwner();
  if ((e.enter = dyn_cast<LinEnterOp>(user))) {
    e.exit = dyn_cast_or_null<LinUseOp>(next(e.enter.getResult()));
    if (!e.exit)
      return std::nullopt;
    user = next(value = e.exit.getResult());
  }
  if ((e.field = dyn_cast_or_null<FieldOp>(user)))
    user = next(value = e.field.getResult());
  if ((e.use = dyn_cast_or_null<LinUseOp>(user)))
    user = next(value = e.use.getResult());
  e.apply = dyn_cast_or_null<ApplyOp>(user);
  if (!e.apply || e.apply.getCallee() != value)
    return std::nullopt;
  return e;
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

  // Every attribute in the program is read by someone: an inherent one by
  // its op, a discardable one by its dialect or by one of our tools.
  WalkResult named = module.walk([&](Operation *op) -> WalkResult {
    if (op != module.getOperation() && failed(verifyDiscardableAttrs(op)))
      return WalkResult::interrupt();
    auto fn = dyn_cast<FunctionOpInterface>(op);
    if (!fn)
      return WalkResult::advance();
    auto check = [&](ArrayRef<DictionaryAttr> dicts, StringRef what) -> LogicalResult {
      for (auto [index, dict] : llvm::enumerate(dicts))
        for (NamedAttribute attr : dict ? dict.getValue() : ArrayRef<NamedAttribute>())
          if (!attr.getNameDialect())
            return fn->emitOpError("has the attribute ")
                   << attr.getName() << " on " << what << " " << index
                   << ", which no dialect defines";
      return success();
    };
    SmallVector<DictionaryAttr> args, results;
    fn.getAllArgAttrs(args);
    fn.getAllResultAttrs(results);
    if (failed(check(args, "argument")) || failed(check(results, "result")))
      return WalkResult::interrupt();
    return WalkResult::advance();
  });
  if (named.wasInterrupted())
    return failure();

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
    // A poison is no value: it stands where a path that is never taken
    // needs one (the payload a loop yields on the path that does not use
    // it), so taking it twice takes nothing. Constant hoisting may put one
    // outside a loop, where every use inside repeats.
    if (quantityOf(value.getType()) != Quantity::One || value.getDefiningOp<ub::PoisonOp>())
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

namespace {

// A rule for one of the dialect's discardable attributes: where it may sit
// and what its value may be.
struct KnownAttr {
  llvm::StringLiteral name;
  LogicalResult (*verify)(Operation *op, NamedAttribute attr);
};

LogicalResult unitOfFunction(Operation *op, NamedAttribute attr) {
  if (!isa<func::FuncOp>(op) || !isa<UnitAttr>(attr.getValue()))
    return op->emitOpError("expects ")
           << attr.getName().getValue() << " as a unit attribute of a function";
  return success();
}

// Where each of the dialect's discardable attributes may sit, and what its
// value may be, by the names its declaration gives them. The verifier asks
// the dialect about every attribute named `idr.*`, so a name missing here is
// rejected, not ignored.
constexpr KnownAttr kKnownAttrs[] = {
    {IdrDialect::ProgramAttrHelper::getNameStr(),
     [](Operation *op, NamedAttribute attr) -> LogicalResult {
       if (!isa<ModuleOp>(op) || !isa<UnitAttr>(attr.getValue()))
         return op->emitOpError("expects idr.program as a unit attribute of the module");
       return verifyProgram(cast<ModuleOp>(op));
     }},
    // After idr-rc every reference is explicit, and consumed exactly once on
    // every path (lib/Ownership).
    {IdrDialect::StageAttrHelper::getNameStr(),
     [](Operation *op, NamedAttribute attr) -> LogicalResult {
       auto stage = dyn_cast<StringAttr>(attr.getValue());
       if (!isa<ModuleOp>(op) || !stage || stage.getValue() != ownership::ownedStage)
         return op->emitOpError("expects idr.stage = \"owned\" on the module");
       return ownership::verifyOwned(cast<ModuleOp>(op));
     }},
    // The facts of a function (lib/Facts): what Idris proves, whether it was
    // written in a library, and what idr-effects finds.
    {IdrDialect::TotalAttrHelper::getNameStr(), unitOfFunction},
    {IdrDialect::LibraryAttrHelper::getNameStr(), unitOfFunction},
    {IdrDialect::EffectsAttrHelper::getNameStr(),
     [](Operation *op, NamedAttribute attr) -> LogicalResult {
       if (!isa<func::FuncOp>(op) || !isa<EffectAttr>(attr.getValue()))
         return op->emitOpError("expects idr.effects = #idr.effects<...> on a function");
       return success();
     }},
    // idr-stack's mark of a box whose cell never leaves its frame
    // (lib/Stack/Pass.cc).
    {IdrDialect::StackAttrHelper::getNameStr(),
     [](Operation *op, NamedAttribute attr) -> LogicalResult {
       auto con = dyn_cast<ConOp>(op);
       if (!con || !isa<BoxType>(con.getType()) || !isa<UnitAttr>(attr.getValue()))
         return op->emitOpError("expects idr.stack as a unit attribute of an idr.con of a box");
       return success();
     }},
    // What idr-specialize keeps on a clone between its runs
    // (lib/Specialize): its key, which also says what it was cloned from.
    {IdrDialect::CloneAttrHelper::getNameStr(),
     [](Operation *op, NamedAttribute attr) -> LogicalResult {
       auto fn = dyn_cast<func::FuncOp>(op);
       auto clone = dyn_cast<CloneAttr>(attr.getValue());
       if (!fn || !clone || clone.getFunction().getAttr() != fn.getSymNameAttr() ||
           !isa<SpecKeyAttr, KeyApplyAttr, KeyApplyFieldAttr>(clone.getKey()))
         return op->emitOpError("expects idr.clone to name the function and its key");
       return success();
     }},
};

// The ownership passes name the attributes they write themselves.
static_assert(std::string_view(ownership::stageAttr) ==
              std::string_view(IdrDialect::StageAttrHelper::getNameStr()));
static_assert(std::string_view(ownership::borrowedAttr) ==
              std::string_view(IdrDialect::BorrowedAttrHelper::getNameStr()));

// The discardable attributes of no dialect that our own tools read. MLIR
// verifies a discardable attribute only through the dialect its name
// starts with, so any other name would be accepted and read by no one.
constexpr llvm::StringLiteral kOutsideDialects[] = {
    // What a test states lib/Facts answers about an op (idr-expect's
    // facts-as-marked).
    "expect.facts",
};

} // namespace

LogicalResult idr::verifyDiscardableAttrs(Operation *op) {
  // Another dialect verifies only the attributes it knows it reads, and
  // accepts the rest of its prefix; none of them is read on an idr op or a
  // function of a program, so these carry only the dialect's own.
  bool ours = isa_and_present<IdrDialect>(op->getDialect()) || isa<FunctionOpInterface>(op);
  for (NamedAttribute attr : op->getDiscardableAttrs()) {
    if (llvm::is_contained(kOutsideDialects, attr.getName().getValue()))
      continue;
    Dialect *dialect = attr.getNameDialect();
    if (!dialect)
      return op->emitOpError("has the attribute ")
             << attr.getName() << ", which no dialect defines";
    if (ours && !isa<IdrDialect>(dialect))
      return op->emitOpError("has the attribute ")
             << attr.getName() << ", which nothing reads on it";
  }
  return success();
}

LogicalResult IdrDialect::verifyOperationAttribute(Operation *op, NamedAttribute attr) {
  for (const KnownAttr &known : kKnownAttrs)
    if (attr.getName().getValue() == known.name)
      return known.verify(op, attr);
  return op->emitOpError("has an unknown idr attribute ") << attr.getName();
}

// A parameter's quantity is its type; the argument attributes are the
// passes' own marks.
LogicalResult IdrDialect::verifyRegionArgAttribute(Operation *op, unsigned,
                                                   unsigned argIndex,
                                                   NamedAttribute attr) {
  auto fn = dyn_cast<FunctionOpInterface>(op);
  // idr-specialize numbers a clone's parameters by the holes of its key.
  if (attr.getName().getValue() == HoleAttrHelper::getNameStr() && fn &&
      isa<IntegerAttr>(attr.getValue()))
    return success();
  // idr-rc's parameters that the function borrows (lib/Ownership).
  if (attr.getName().getValue() == BorrowedAttrHelper::getNameStr() && fn) {
    if (!isa<UnitAttr>(attr.getValue()) ||
        !isa<StrType, BigType, NatType, BoxType, FnType, DataType>(fn.getArgumentTypes()[argIndex]))
      return op->emitOpError("expects idr.borrowed as a unit attribute of a parameter that "
                             "holds references, not of argument ")
             << argIndex;
    return success();
  }
  return op->emitOpError("has an unknown idr argument attribute ") << attr.getName();
}
