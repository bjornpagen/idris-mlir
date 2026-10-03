// The idr dialect: types, attributes, constants, and the rules of the module
// and of its functions.

#include "idr/Idr.h"

#include "Dialect/Sharing.h"
#include "Ownership/Ownership.h"

#include "mlir/Dialect/MemRef/Transforms/Transforms.h"
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

// The dimension of an array, `memref.dim` of an `idr.array.new`, is the
// size the array was made with: upstream's resolution of a dimension
// through ReifyRankedShapedTypeOpInterface, which idr.array.new
// implements, as a canonicalization.
void IdrDialect::getCanonicalizationPatterns(RewritePatternSet &results) const {
  memref::populateResolveRankedShapedTypeResultDimsPatterns(results);
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
  if (isWorld(type) || isErased(type))
    return true;
  type = unrestricted(type);
  if (auto integer = dyn_cast<IntegerType>(type))
    return integer.isSignless() && llvm::is_contained({8u, 16u, 32u, 64u}, integer.getWidth());
  return isa<Float64Type, DataType, BoxType, FnType, StrType, BigType, NatType>(type) ||
         isArray(type);
}

// One dynamic dimension in the identity layout: the shape the runtime's
// array cell has (a length, then the elements in order). An element is a
// field type at no grade, and not the world or the erased value, which
// have no runtime form to store.
bool idr::isArray(Type type) {
  auto memref = dyn_cast<MemRefType>(type);
  if (!memref || memref.getRank() != 1 || !memref.isDynamicDim(0) ||
      !memref.getLayout().isIdentity() || memref.getMemorySpace())
    return false;
  Type element = memref.getElementType();
  return !isa<QType>(element) && !isWorld(element) && !isErased(element) && isFieldType(element);
}

//===----------------------------------------------------------------------===//
// Grades
//===----------------------------------------------------------------------===//

// The canonical forms: a plain type is (ω, ·) and is never written as a
// grade; a grade is of a carrier, never of a grade; nothing is owned at
// quantity 0; the erased value, of no carrier, is at quantity 0; the world
// is at (1, ·) only; a linear value has a runtime type.
LogicalResult QType::verify(function_ref<InFlightDiagnostic()> emitError, Grade grade,
                            Type value) {
  if (grade.plain())
    return emitError() << "expects a grade other than (w, .), which is the plain type";
  if (isa<QType>(value))
    return emitError() << "expects a grade of a plain type, got one of " << value;
  if (grade.quantity == Quantity::Zero && grade.permission != Permission::None)
    return emitError() << "expects nothing owned at quantity 0";
  if (isa<NoneType>(value) != (grade.quantity == Quantity::Zero))
    return emitError() << "expects the erased value, and only it, at quantity 0";
  if (isa<WorldType>(value)) {
    if (grade != Grade{Quantity::One, Permission::None})
      return emitError() << "expects the world at quantity 1, owning nothing";
    return success();
  }
  // A runtime type: one a field may have, or a token, which is owned.
  if (grade.quantity != Quantity::Zero && !isFieldType(value) && !isa<TokenType>(value))
    return emitError() << "expects a grade of a runtime type, got " << value;
  return success();
}

namespace {

constexpr StringRef quantityNames[] = {"0", "1", "w"};
constexpr StringRef permissionNames[] = {"", "borrow", "own", "excl"};

// The generic spelling of a grade: the quantity, then the permission when
// there is one to say: `1`, `w own`, `1 excl`.
void printGrade(AsmPrinter &printer, Grade grade) {
  printer << quantityNames[static_cast<unsigned>(grade.quantity)];
  if (grade.permission != Permission::None)
    printer << ' ' << permissionNames[static_cast<unsigned>(grade.permission)];
}

std::optional<Grade> parseGrade(AsmParser &parser) {
  Grade grade;
  uint64_t number = 0;
  StringRef word;
  OptionalParseResult parsed = parser.parseOptionalInteger(number);
  if (parsed.has_value() && succeeded(*parsed) && number <= 1) {
    grade.quantity = number == 0 ? Quantity::Zero : Quantity::One;
  } else if (!parsed.has_value() && succeeded(parser.parseOptionalKeyword("w"))) {
    grade.quantity = Quantity::Many;
  } else {
    parser.emitError(parser.getCurrentLocation(), "expects a quantity 0, 1 or w");
    return std::nullopt;
  }
  if (succeeded(parser.parseOptionalKeyword(&word))) {
    auto permission = llvm::find(permissionNames, word);
    if (permission == std::end(permissionNames)) {
      parser.emitError(parser.getCurrentLocation(), "expects a permission borrow, own or excl");
      return std::nullopt;
    }
    grade.permission = static_cast<Permission>(permission - std::begin(permissionNames));
  }
  return grade;
}

} // namespace

// `!idr.q<GRADE, T>`, the generic spelling; `!idr.q<0>` for the erased
// value. The spellings lin, erased and world are the dialect's to parse
// and print.
Type QType::parse(AsmParser &parser) {
  if (parser.parseLess())
    return {};
  std::optional<Grade> grade = parseGrade(parser);
  if (!grade)
    return {};
  Type value = NoneType::get(parser.getContext());
  if (succeeded(parser.parseOptionalComma()) && parser.parseType(value))
    return {};
  if (parser.parseGreater())
    return {};
  return QType::getChecked([&] { return parser.emitError(parser.getCurrentLocation()); },
                           parser.getContext(), *grade, value);
}

void QType::print(AsmPrinter &printer) const {
  printer << '<';
  printGrade(printer, getGrade());
  if (!isa<NoneType>(getValue()))
    printer << ", " << getValue();
  printer << '>';
}

Grade idr::gradeOf(Type type) {
  auto q = dyn_cast<QType>(type);
  return q ? q.getGrade() : Grade{};
}

Type idr::graded(Grade grade, Type value) {
  if (auto q = dyn_cast<QType>(value))
    value = q.getValue();
  return grade.plain() ? value : QType::get(value.getContext(), grade, value);
}

Type idr::linear(Type value) { return graded({Quantity::One, Permission::None}, value); }

Type idr::erased(MLIRContext *ctx) {
  return graded({Quantity::Zero, Permission::None}, NoneType::get(ctx));
}

Type idr::world(MLIRContext *ctx) {
  return graded({Quantity::One, Permission::None}, WorldType::get(ctx));
}

// The world and the erased value are known by their carriers, graded or
// not: a carrier that a grade was stripped from (unrestricted) is still
// the value it is.
bool idr::isWorld(Type type) { return isa<WorldType>(unrestricted(type)); }

bool idr::isErased(Type type) { return isa<NoneType>(unrestricted(type)); }

bool idr::isLinear(Type type) {
  return gradeOf(type).quantity == Quantity::One && !isWorld(type);
}

bool idr::isOwned(Type type) {
  Permission permission = gradeOf(type).permission;
  return permission == Permission::Own || permission == Permission::Excl;
}

Type idr::owned(Type type) {
  Grade grade = gradeOf(type);
  if (grade.permission == Permission::None)
    grade.permission = Permission::Own;
  return graded(grade, unrestricted(type));
}

Type idr::view(Type type) {
  return graded({gradeOf(type).quantity, Permission::None}, unrestricted(type));
}

Type idr::atQuantity(Type type, Quantity quantity) {
  return graded({quantity, gradeOf(type).permission}, unrestricted(type));
}

bool idr::isExclusive(Type type) { return gradeOf(type).permission == Permission::Excl; }

Quantity idr::times(Quantity a, Quantity b) {
  if (a == Quantity::Zero || b == Quantity::Zero)
    return Quantity::Zero;
  if (a == Quantity::One)
    return b;
  if (b == Quantity::One)
    return a;
  return Quantity::Many;
}

Type idr::fieldType(Type scrutinee, Type field) {
  if (isWorld(field))
    return field;
  return graded({times(quantityOf(scrutinee), quantityOf(field)), Permission::None},
                unrestricted(field));
}

Value idr::heldAs(OpBuilder &b, Location loc, Value value, Type type) {
  if (value.getType() == type)
    return value;
  if (quantityOf(type) == Quantity::One)
    return LinEnterOp::create(b, loc, type, value);
  return LinUseOp::create(b, loc, type, value);
}

// The spellings: !idr.lin<T> is (1, ·) of T, !idr.own<T> is (ω, own) of
// T, !idr.erased is (0, ·) of no carrier, !idr.world is (1, ·) of the
// world; any other grade is written out as !idr.q. The world's carrier is
// never written by itself.
Type IdrDialect::parseType(DialectAsmParser &parser) const {
  llvm::SMLoc loc = parser.getCurrentLocation();
  MLIRContext *ctx = parser.getContext();
  if (succeeded(parser.parseOptionalKeyword("lin"))) {
    Type value;
    if (parser.parseLess() || parser.parseType(value) || parser.parseGreater())
      return {};
    return QType::getChecked([&] { return parser.emitError(loc); }, ctx,
                             Grade{Quantity::One, Permission::None}, value);
  }
  if (succeeded(parser.parseOptionalKeyword("own"))) {
    Type value;
    if (parser.parseLess() || parser.parseType(value) || parser.parseGreater())
      return {};
    return QType::getChecked([&] { return parser.emitError(loc); }, ctx,
                             Grade{Quantity::Many, Permission::Own}, value);
  }
  if (succeeded(parser.parseOptionalKeyword("excl"))) {
    Type value;
    if (parser.parseLess() || parser.parseType(value) || parser.parseGreater())
      return {};
    return QType::getChecked([&] { return parser.emitError(loc); }, ctx,
                             Grade{Quantity::Many, Permission::Excl}, value);
  }
  if (succeeded(parser.parseOptionalKeyword("erased")))
    return erased(ctx);
  if (succeeded(parser.parseOptionalKeyword("world")))
    return world(ctx);
  // The generated parser reads the mnemonic itself.
  StringRef mnemonic;
  Type type;
  OptionalParseResult result = generatedTypeParser(parser, &mnemonic, type);
  if (result.has_value())
    return type;
  parser.emitError(loc) << "unknown type `" << mnemonic << "` in dialect `idr`";
  return {};
}

void IdrDialect::printType(Type type, DialectAsmPrinter &printer) const {
  if (auto q = dyn_cast<QType>(type)) {
    if (isWorld(q)) {
      printer << "world";
    } else if (isErased(q) && q.getGrade().permission == Permission::None) {
      printer << "erased";
    } else if (isLinear(q) && q.getGrade().permission == Permission::None) {
      printer << "lin<" << q.getValue() << '>';
    } else if (q.getGrade() == Grade{Quantity::Many, Permission::Own}) {
      printer << "own<" << q.getValue() << '>';
    } else if (q.getGrade() == Grade{Quantity::Many, Permission::Excl}) {
      printer << "excl<" << q.getValue() << '>';
    } else {
      printer << "q";
      q.print(printer);
    }
    return;
  }
  if (failed(generatedTypePrinter(type, printer)))
    llvm_unreachable("a type of the idr dialect");
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
  return isa<DestType>(type) ? Quantity::One : gradeOf(type).quantity;
}

Type idr::unrestricted(Type type) {
  auto q = dyn_cast<QType>(type);
  return q ? q.getValue() : type;
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

bool idr::fieldReadOnce(Value value, unsigned index) {
  unsigned reads = 0;
  SmallVector<Value, 4> work{value};
  while (!work.empty()) {
    Value held = work.pop_back_val();
    for (Operation *user : held.getUsers()) {
      if (isa<LinEnterOp, LinUseOp>(user)) {
        work.push_back(user->getResult(0));
        continue;
      }
      auto read = dyn_cast<FieldOp>(user);
      if (!read)
        return false;
      if (read.getIndex() == index)
        ++reads;
    }
  }
  return reads == 1;
}

//===----------------------------------------------------------------------===//
// Lookup helpers
//===----------------------------------------------------------------------===//

FlatSymbolRefAttr idr::getSumName(Type type) {
  return TypeSwitch<Type, FlatSymbolRefAttr>(unrestricted(type))
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
  bool ioRoot = root.getInputs().size() == 1 && isWorld(root.getInput(0));
  if (!intRoot && !ioRoot)
    return roots.front().emitOpError("is the root, so its type must be () -> i64 or "
                                     "(!idr.world) -> (...), not ")
           << root;

  // No function body ends in ub.unreachable, which the pinned inliner
  // cannot inline: a body that never returns returns poison, which is never
  // reached (returnNever). A match region may end in it.
  // PIN(inline-unreachable) — see PINS.md
  for (auto fn : module.getOps<func::FuncOp>())
    for (Block &block : fn.getBody())
      if (!block.empty() && isa<ub::UnreachableOp>(block.back()))
        return block.back().emitOpError("ends the body of @")
               << fn.getSymName() << ", where a body that never returns returns poison";

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
    // A view of the value (idr.borrow) is not a use of it: the owner keeps
    // its reference, and the view's uses come before the owner's one use.
    unsigned total =
        isa<BorrowOp>(op) ? 0u : static_cast<unsigned>(llvm::count(op->getOperands(), world));
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
      return op->emitOpError(isWorld(value.getType())
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
    // The facts of a function (lib/Facts): what Idris proves, whether a
    // cycle breaks at it last, and what idr-effects finds.
    {IdrDialect::TotalAttrHelper::getNameStr(), unitOfFunction},
    {IdrDialect::BreakLastAttrHelper::getNameStr(), unitOfFunction},
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
       if (!con || !isa<BoxType>(unrestricted(con.getType())) || !isa<UnitAttr>(attr.getValue()))
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

// The discardable attributes of no dialect that our own tools read. MLIR
// verifies a discardable attribute only through the dialect its name
// starts with, so any other name would be accepted and read by no one.
constexpr llvm::StringLiteral kOutsideDialects[] = {
    // What a test states lib/Facts answers about an op (idr-expect's
    // facts-as-marked).
    "expect.facts",
};

} // namespace

// What `op` alone does, nested ops aside: nothing, when it has no effects
// or all of them are allocations of its results; IO, when it reads the IO
// resource (a crash and a loop that may not end only write it, which
// orders them after output without making them output); otherwise
// something. An op whose effects MLIR does not know may do anything.
namespace {
enum class Does { Nothing, IO, Something };
Does does(Operation *op) {
  if (op->hasTrait<OpTrait::HasRecursiveMemoryEffects>() || isa<ub::UnreachableOp>(op))
    return Does::Nothing;
  auto iface = dyn_cast<MemoryEffectOpInterface>(op);
  if (!iface)
    return Does::Something;
  SmallVector<MemoryEffects::EffectInstance> effects;
  iface.getEffects(effects);
  Does out = Does::Nothing;
  for (const MemoryEffects::EffectInstance &effect : effects) {
    if (effect.getResource() == IOResource::get() && isa<MemoryEffects::Read>(effect.getEffect()))
      return Does::IO;
    if (!isa<MemoryEffects::Allocate>(effect.getEffect()) ||
        !isa_and_present<OpResult>(effect.getValue()))
      out = Does::Something;
  }
  return out;
}
} // namespace

bool idr::onlyAllocates(Operation *op) {
  return !op->walk([](Operation *inner) {
              return does(inner) == Does::Nothing ? WalkResult::advance() : WalkResult::interrupt();
            })
              .wasInterrupted();
}

bool idr::performsIO(Operation *op) {
  return op->walk([](Operation *inner) {
             return does(inner) == Does::IO ? WalkResult::interrupt() : WalkResult::advance();
           })
      .wasInterrupted();
}

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
LogicalResult IdrDialect::verifyRegionArgAttribute(Operation *op, unsigned, unsigned,
                                                   NamedAttribute attr) {
  auto fn = dyn_cast<FunctionOpInterface>(op);
  // idr-specialize numbers a clone's parameters by the holes of its key.
  if (attr.getName().getValue() == HoleAttrHelper::getNameStr() && fn &&
      isa<IntegerAttr>(attr.getValue()))
    return success();
  return op->emitOpError("has an unknown idr argument attribute ") << attr.getName();
}
