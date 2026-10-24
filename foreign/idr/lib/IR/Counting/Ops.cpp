// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The hooks of counting's ops that move references (a dup, a share, the
// null token, a crossing into upstream's buffers), and what every op of
// counting asks: the predicates their operands satisfy, the rule for what a
// field of a built value holds, and the size check of a recycle. A value is
// taken apart and rebuilt in Takes.cpp, and a cell is filled in
// CellInit.cpp. Every fact a type states (who frees a value, what it claims
// of its sharing) is read off the type, so a value typed unique meets no
// count op and no test of its sharing, and a view is never duplicated or
// dropped. A share passes a scoped value through, so it states the lifetime
// of the value it gives, one step from it.

#include "idr/IR/Counting/Counting.h"
#include "idr/IR/Families/Families.h"
#include "idr/IR/Grades.h"
#include "idr/IR/IdrDialect.h"
#include "idr/IR/Layout.h"
#include "idr/IR/Lifetimes.h"
#include "idr/IR/Ranges.h"

#include "mlir/IR/OpImplementation.h"
#include "llvm/ADT/STLExtras.h"

using namespace mlir;
using namespace idr;

//===----------------------------------------------------------------------===//
// What the operands ask
//===----------------------------------------------------------------------===//

namespace idr {

// A hold exists exactly where the carrier holds references (GradedType's
// verifier, and a bare carrier's grade), so the release alone answers.
bool isCountedValue(Type value) { return freedBy(value, Release::Counted); }

// A value its uses do not bound: one a dup may copy, never a linear one.
bool isUsedMany(Type value) { return usesOf(value) == Uses::Many; }

bool isTokenValue(Type value) {
  return isa<ReuseTokenType>(unrestricted(value)) && usesOf(value) == Uses::Once;
}

bool isHeldValue(Type value) { return holdOf(value).has_value(); }

} // namespace idr

//===----------------------------------------------------------------------===//
// What a field holds
//===----------------------------------------------------------------------===//

bool idr::fillsField(Type type, Type field, std::optional<Hold> built) {
  Type carrier = unrestricted(field);
  if (unrestricted(type) != carrier && !families::refines(unrestricted(type), carrier))
    return false;
  if (usesOf(type) == Uses::Once && usesOf(field) != Uses::Once)
    return false;
  std::optional<Hold> held = holdOf(type);
  return !held || held->fits(Hold::counted()) || held->fits(Hold::staticData()) ||
         (built && built->release() == Release::Scoped);
}

LogicalResult idr::verifyRecycle(CellRecycleOp recycle, const Layouts &layouts) {
  CellType cell = recycle.getCell().getType();
  unsigned need = layouts.cells(cell.getData()).cell(cell.getTag()).size;
  auto token = cast<ReuseTokenType>(unrestricted(recycle.getToken().getType()));
  for (Type source : token.getSources()) {
    auto data = cast<DataType>(source);
    unsigned have = layouts.cells(data).cell(*data.singleTag()).size;
    if (have != need)
      return recycle.emitOpError("gives a cell of ")
             << need << " bytes from a token that may hold the " << have << "-byte cell of "
             << source;
  }
  return success();
}

namespace idr {

// A share's result: the value with its claim forgotten, unless another
// type it fits is written, `-> T`.
ParseResult parseShared(OpAsmParser &parser, Type &result, Type value) {
  if (succeeded(parser.parseOptionalArrow()))
    return parser.parseType(result);
  result = shared(value);
  return success();
}

void printShared(OpAsmPrinter &printer, Operation *, Type result, Type value) {
  if (result != shared(value))
    printer << " -> " << result;
}

} // namespace idr

//===----------------------------------------------------------------------===//
// Dup, share
//===----------------------------------------------------------------------===//

// One more reference makes the value shared: a value whose type claims its
// own cells unshared (its family's, and each in-place family's it holds)
// has none to give, and the result claims nothing.
LogicalResult CountDupOp::verify() {
  Type value = getValue().getType();
  Type result = getResult().getType();
  if (claims(value, Unique::Self))
    return emitOpError("duplicates ") << value << ", whose type claims it unshared";
  if (unrestricted(result) != unrestricted(value) || holdOf(result) != Hold::counted())
    return emitOpError("gives ") << result << ", which is not " << unrestricted(value)
                                 << " counted, claiming nothing";
  return success();
}

namespace {

// Whether a token of `from` may stand where one of `to` is asked: at the
// same uses, its hold fitting, `to` naming every cell `from` may hold.
bool widens(Type from, Type to) {
  auto a = dyn_cast<ReuseTokenType>(unrestricted(from));
  auto b = dyn_cast<ReuseTokenType>(unrestricted(to));
  if (!a || !b || usesOf(from) != usesOf(to))
    return false;
  std::optional<Hold> held = holdOf(from);
  std::optional<Hold> asked = holdOf(to);
  if (!held || !asked || !held->fits(*asked))
    return false;
  return llvm::all_of(a.getSources(),
                      [&](Type source) { return llvm::is_contained(b.getSources(), source); });
}

} // namespace

// A scoped result lives where its operand does, unless the share is given
// another lifetime: static data shared into a scoped slot names the slot's.
void CountShareOp::build(OpBuilder &builder, OperationState &state, Type result, Value value) {
  Value lifetime = freedBy(result, Release::Scoped) ? lifetimes::statedLifetime(value) : Value();
  build(builder, state, result, value, lifetime ? ValueRange(lifetime) : ValueRange());
}

Value CountShareOp::getStatedLifetime(Value made) { return lifetimes::statedOuter(*this, made, 0); }

void CountShareOp::setStatedLifetime(Value made, Value lifetime) {
  lifetimes::stateOuter(*this, made, lifetime, 0);
}

// The result is the operand's value, so its range is the operand's.
void CountShareOp::inferResultRangesFromOptional(ArrayRef<IntegerValueRange> ranges,
                                                 SetIntLatticeFn setResultRange) {
  ranges::carried(getResult(), ranges.front(), setResultRange);
}

// That the stated lifetime is the operand's or one it encloses is the
// lifetimes' verifier's, which knows what is open where the share stands.
LogicalResult CountShareOp::verify() {
  Type value = getValue().getType();
  Type result = getResult().getType();
  if (!forgets(value, result) && !widens(value, result))
    return emitOpError("gives ") << value << " as " << result
                                 << ", which is no less than it claims";
  return lifetimes::verifyOuters(*this, 0);
}

//===----------------------------------------------------------------------===//
// The null token
//===----------------------------------------------------------------------===//

// The null token is shared by its making: it holds no cell.
LogicalResult TokenNullOp::verify() {
  if (claims(getToken().getType(), Unique::Self))
    return emitOpError("gives a null token typed as holding its cell");
  return success();
}

//===----------------------------------------------------------------------===//
// Crossings into upstream's buffers
//===----------------------------------------------------------------------===//

// The buffer is fresh and nothing moves into it, so it claims everything it
// reaches unshared; its operand is the bare buffer, as its constraint says.
// That is the most its result may claim, not the grade it is made at:
// bufferization, which makes it, writes the bare buffer, since before
// references are counted the stage rule holds a value used many times to
// claiming nothing; exclusivity writes the claim from the owned stage,
// where it proves it.
LogicalResult OwnAdoptOp::inferReturnTypes(MLIRContext *, std::optional<Location>, Adaptor adaptor,
                                           SmallVectorImpl<Type> &inferred) {
  inferred.push_back(graded(Grade{Uses::Many, Hold::counted(Unique::Deep)}, adaptor.getValue().getType()));
  return success();
}

// The adopted buffer at any grade that only forgets what it claims: the bare
// buffer where upstream's ops read it.
bool OwnAdoptOp::isCompatibleReturnTypes(TypeRange inferred, TypeRange actual) {
  return inferred.size() == 1 && actual.size() == 1 && forgets(inferred.front(), actual.front());
}

// The store takes the plain carrier: the value's type, its grade forgotten.
LogicalResult OwnGiveOp::inferReturnTypes(MLIRContext *, std::optional<Location>, Adaptor adaptor,
                                          SmallVectorImpl<Type> &inferred) {
  inferred.push_back(unrestricted(adaptor.getValue().getType()));
  return success();
}

// The store takes the plain carrier, so a value used once is never given:
// its quantity would be lost.
LogicalResult OwnGiveOp::verify() {
  Type value = getValue().getType();
  if (usesOf(value) == Uses::Once)
    return emitOpError("gives ") << value << " to memory, which would lose its one use";
  return success();
}
