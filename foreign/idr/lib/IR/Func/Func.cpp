// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// idr.program and idr.func: the closed program, whose root is its property
// and whose region verifier checks the root and runs the program's rules; a
// function's text, its effects before its symbol and no visibility written,
// since its program's root decides it; and the rules of one function at its
// program's stage, which run after the ops of its body are verified and in
// parallel with every other function's. Then what a body does, of itself
// and with its calls; the one writer of a function's effects; the table of
// what each effect bit is to MLIR; and the rule of the root.

#include "idr/IR/Func.h"
#include "idr/IR/Grades.h"
#include "idr/IR/IdrDialect.h"
#include "idr/IR/Layout.h"
#include "idr/IR/Verify.h"

#include "mlir/Dialect/Func/IR/FuncOps.h"
#include "mlir/IR/Builders.h"
#include "mlir/IR/BuiltinTypes.h"
#include "mlir/IR/DialectImplementation.h"
#include "mlir/IR/OpImplementation.h"
#include "mlir/IR/SymbolTable.h"
#include "mlir/Interfaces/FunctionImplementation.h"
#include "mlir/Interfaces/FunctionInterfaces.h"
#include "llvm/ADT/STLExtras.h"
#include "llvm/ADT/SmallPtrSet.h"

using namespace mlir;
using namespace idr;

//===----------------------------------------------------------------------===//
// idr.program
//===----------------------------------------------------------------------===//

void idr::ProgramOp::build(OpBuilder &builder, OperationState &state, StringRef name,
                           StringRef root, Stage stage) {
  Properties &properties = state.getOrAddProperties<Properties>();
  properties.sym_name = builder.getStringAttr(name);
  properties.root = FlatSymbolRefAttr::get(builder.getContext(), root);
  properties.stage = StageAttr::get(builder.getContext(), stage);
  properties.types = DataTableAttr::get(builder.getContext(), ArrayRef<DataType>{});
  state.addRegion()->emplaceBlock();
}

void idr::ProgramOp::declare(DataType data) { setTypesAttr(getTypes().with(data)); }

// A module holds one program, the closed world every pass reads: the first
// in its module's block, and none after it. Only that block's ops are read,
// which no pass on a program changes.
LogicalResult idr::ProgramOp::verify() {
  ProgramOp first = *(*this)->getBlock()->getOps<ProgramOp>().begin();
  if (first != *this)
    return emitOpError("@") << getSymName() << " is a second program beside @"
                            << first.getSymName() << ", and a module holds one program";
  return success();
}

FuncOp idr::ProgramOp::lookupRoot() {
  return dyn_cast_or_null<FuncOp>(
      mlir::SymbolTable::lookupSymbolIn(getOperation(), getRootAttr().getAttr()));
}

// The root, checked once: a function of the program of the kind its stage
// holds (an idr.func until the program is lowered, upstream's func.func
// after, which are two kinds of function), whose type rootKind accepts at
// the stage. Then the program's rules. MLIR runs this after every op of the
// program is verified and, by the program's symbol table, every call's
// symbol uses (a call's effects contain its callee's); on one thread; when
// the module is read and after every pass on the program, so a program pass
// that breaks a rule fails where it breaks it.
LogicalResult idr::ProgramOp::verifyRegions() {
  Operation *root = mlir::SymbolTable::lookupSymbolIn(getOperation(), getRootAttr().getAttr());
  bool idrFunctions = stageFacts(getStage()).idrFunctions();
  if (idrFunctions ? !isa_and_nonnull<FuncOp>(root) : !isa_and_nonnull<func::FuncOp>(root))
    return emitOpError("has root ")
           << getRootAttr() << ", which is no "
           << (idrFunctions ? FuncOp::getOperationName() : func::FuncOp::getOperationName())
           << " of the program";
  auto type = cast<FunctionType>(cast<FunctionOpInterface>(root).getFunctionType());
  if (!rootKind(type, getStage()))
    return root->emitOpError("is the root, so its type must be () -> i64, or before lowering "
                             "(!idr.world) -> (...) with no result holding a runtime value, "
                             "or lowered () -> (); not ")
           << type;
  return verify::program(*this);
}

//===----------------------------------------------------------------------===//
// idr.func
//===----------------------------------------------------------------------===//

ProgramOp idr::FuncOp::getProgram() { return cast<ProgramOp>((*this)->getParentOp()); }

bool idr::FuncOp::isRoot() {
  auto program = dyn_cast_or_null<ProgramOp>((*this)->getParentOp());
  return program && program.getRootAttr() &&
         program.getRootAttr().getAttr() == getSymNameAttr();
}

// func.func's syntax without its visibility, which the program's root
// decides, and with its effects before its symbol, `idr.func effects<io>
// @f(...)`, written only when they are not the default: a property, which
// no attribute dictionary holds, so parseFunctionOp, which reads the
// other facts from `attributes`, cannot read it. Then the body's ops
// without the dialect's prefix.
ParseResult idr::FuncOp::parse(OpAsmParser &parser, OperationState &result) {
  if (succeeded(parser.parseOptionalKeyword("effects"))) {
    FailureOr<Effect> effects = failure();
    if (parser.parseLess() || failed(effects = FieldParser<Effect>::parse(parser)) ||
        parser.parseGreater())
      return failure();
    result.getOrAddProperties<Properties>().effects = *effects;
  }
  auto buildFuncType = [](Builder &builder, ArrayRef<Type> inputs, ArrayRef<Type> results,
                          function_interface_impl::VariadicFlag, std::string &) {
    return FunctionType::get(builder.getContext(), inputs, results);
  };
  SMLoc loc = parser.getCurrentLocation();
  if (failed(function_interface_impl::parseFunctionOp(
          parser, result, /*allowVariadic=*/false, getFunctionTypeAttrName(result.name),
          buildFuncType, getArgAttrsAttrName(result.name), getResAttrsAttrName(result.name))))
    return failure();
  if (result.attributes.get(SymbolOpInterface::getDefaultVisibilityAttrName()))
    return parser.emitError(loc, "a function's visibility is not written: its program's root is "
                                 "public, and every other function private");
  // The facts arrive in `result.attributes` and become properties when
  // the op is created, which silently drops one of the wrong kind; the
  // generic parser checks them first, and a custom one must too.
  return verifyInherentAttrs(result.name, result.attributes, [&]() {
    return mlir::emitError(result.location) << "'" << result.name.getStringRef() << "' op ";
  });
}

void idr::FuncOp::print(OpAsmPrinter &printer) {
  if (getEffects() != anyEffect)
    printer << " effects<" << getEffects() << '>';
  function_interface_impl::printFunctionOp(printer, *this, /*isVariadic=*/false,
                                           getFunctionTypeAttrName(), getArgAttrsAttrName(),
                                           getResAttrsAttrName());
}

// The interface's own body check has matched the entry block to the type,
// and the ops' verifiers have run: a match's regions and yields are well
// formed. The rest is the function's rules at its program's stage.
LogicalResult idr::FuncOp::verifyRegions() { return verify::function(*this); }

//===----------------------------------------------------------------------===//
// What a body does
//===----------------------------------------------------------------------===//

// A world reaches a function only through a parameter, so IO is read off
// the signature, and off the body only where it forges a world, IO no
// parameter announces. An op that runs a label runs a function no symbol
// names, which may do anything.
Effect idr::bodyEffect(FuncOp fn) {
  Effect own = fn.getTotal() ? Effect::none : Effect::diverge;
  if (llvm::any_of(fn.getArgumentTypes(), idr::holdsWorld))
    own = own | Effect::io;
  fn.getBody().walk([&](Operation *op) {
    if (isa<MayCrashOpInterface>(op))
      own = own | Effect::crash;
    if (isa<WorldNewOp>(op))
      own = own | Effect::io;
    if (isa<RunsLabelsOpInterface>(op))
      own = own | anyEffect;
  });
  return own;
}

// A call of a member is no edge out of the component: the member's own
// part is in the sum, and the solve gives the members one set. Every call
// of the closed world names an idr.func of the program.
Effect idr::componentEffects(ArrayRef<FuncOp> component, const SymbolTable &symbols) {
  llvm::SmallPtrSet<Operation *, 8> members;
  for (FuncOp member : component)
    members.insert(member.getOperation());
  Effect sum = Effect::none;
  for (FuncOp member : component) {
    sum = sum | bodyEffect(member);
    member.getBody().walk([&](CallOp call) {
      if (!members.contains(symbols.lookup(call.getCalleeAttr().getAttr())))
        sum = sum | call.getEffects();
    });
  }
  return sum;
}

// A symbol's users are its calls and the values that name it (a closure's
// constant names its function), which hold no effects: only a call is
// written.
void idr::writeEffects(FuncOp fn, Effect effects, const SymbolUserMap &users) {
  fn.setEffects(effects);
  for (Operation *user : users.getUsers(fn))
    if (auto call = dyn_cast<CallOp>(user))
      call.setEffects(effects);
}

namespace {

// One row of the table: a bit, and one effect on one resource it stands
// for, as the op that has it declares it.
template <typename Access, typename Resource>
void appendEffect(SmallVectorImpl<MemoryEffects::EffectInstance> &instances) {
  instances.emplace_back(Access::get(), Resource::get());
}

struct Row {
  Effect bit;
  void (*append)(SmallVectorImpl<MemoryEffects::EffectInstance> &);
};

// IO reads and writes the IO resource, as the idr.io ops declare it; a
// crash writes the crash resource and the IO resource, as idr.crash and
// every check declare it (Idr_MayCrash); not returning writes the
// divergence resource, as idr.may_loop declares it.
constexpr Row rows[] = {
    {Effect::io, appendEffect<MemoryEffects::Read, IOResource>},
    {Effect::io, appendEffect<MemoryEffects::Write, IOResource>},
    {Effect::crash, appendEffect<MemoryEffects::Write, CrashResource>},
    {Effect::crash, appendEffect<MemoryEffects::Write, IOResource>},
    {Effect::diverge, appendEffect<MemoryEffects::Write, DivergenceResource>},
};

} // namespace

void idr::effectInstances(Effect effects,
                          SmallVectorImpl<MemoryEffects::EffectInstance> &instances) {
  for (const Row &row : rows)
    if (bitEnumContainsAll(effects, row.bit))
      row.append(instances);
}

//===----------------------------------------------------------------------===//
// The root
//===----------------------------------------------------------------------===//

// Before lowering an IO root takes the world and gives back what holds no
// runtime value (the world, a unit, an IO result of a unit); lowered, the
// world and those results have no form, and it takes and gives nothing.
// The two stages are two levels of the IR, each with its own form.
std::optional<RootKind> idr::rootKind(FunctionType type, Stage stage) {
  if (type.getNumInputs() == 0 && type.getNumResults() == 1 &&
      type.getResult(0) == Builder(type.getContext()).getI64Type())
    return RootKind::Status;
  bool io = stageFacts(stage).idrFunctions()
                ? type.getNumInputs() == 1 && isWorld(type.getInput(0)) &&
                      llvm::all_of(type.getResults(),
                                   [](Type result) { return layout::holdsNoComponent(result); })
                : type.getNumInputs() == 0 && type.getNumResults() == 0;
  if (io)
    return RootKind::IO;
  return std::nullopt;
}
