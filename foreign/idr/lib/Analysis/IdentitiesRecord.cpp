// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The one read of a function whose results might give back its arguments.
//
// Each value is numbered in walk order and given how it is built: an entry
// argument; the same value as another or a field of a refined value
// (idr::sourceOf); a call's result; a constructor; a natural's successor or
// predecessor; a match's result; a constant; or opaque. A call is resolved
// to its callee's id once, here. The read writes nothing outside the
// record and reads the body once.
#include "Solver/IdentityRecords.h"

#include "idr/IR/Families/Families.h"
#include "idr/IR/Grades.h"
#include "idr/IR/IdrDialect.h"

#include "mlir/IR/Matchers.h"
#include "mlir/Interfaces/ControlFlowInterfaces.h"
#include "mlir/Interfaces/SideEffectInterfaces.h"
#include "llvm/ADT/STLExtras.h"

using namespace mlir;

namespace idr::identities {

// One value at run time: the same carrier, or two applications of one
// family member whose layout is the same, so the bits of one are the bits
// of the other (Fin n and Fin (S n) after their indices are erased).
Represents representation(Type a, Type b) {
  Type left = unrestricted(a), right = unrestricted(b);
  if (left == right)
    return Represents::Alike;
  auto l = dyn_cast<DataType>(left), r = dyn_cast<DataType>(right);
  if (l && r && l.getGroup() == r.getGroup() && l.getMember() == r.getMember() &&
      l.layout() == r.layout())
    return Represents::Alike;
  return Represents::Differently;
}

namespace {

// A big or natural constant one: what a successor adds.
bool isOne(Value value) {
  BigAttr big;
  return matchPattern(value, m_Constant(&big)) && big.getValue().isOne();
}

// The tag of a constant constructor with no fields: the one value it has.
std::optional<Tag> fieldlessTag(Attribute constant, Type type) {
  auto con = dyn_cast<ConAttr>(constant);
  auto data = dyn_cast<DataType>(unrestricted(type));
  if (!con || !data || !data.ctor(con.getTag()).fields.empty())
    return std::nullopt;
  return con.getTag();
}

template <solver::FunctionNames N>
class Reader {
public:
  Reader(const N &names, FuncOp fn, Record &out, const solver::Numbering<ValueTag> &numbering)
      : names(names), fn(fn), out(out), numbering(numbering) {}

  Build buildOf(Value value);
  void readReturns();

private:
  Range push(ValueRange values) {
    Range range{static_cast<std::uint32_t>(out.operands.size()), 0};
    for (Value value : values)
      out.operands.push_back(numbering.at(value));
    range.count = static_cast<std::uint32_t>(out.operands.size()) - range.first;
    return range;
  }
  Range framesAt(Operation *at);
  Build ofResult(OpResult result);
  std::uint32_t sideOf(Operation *match);

  const N &names;
  FuncOp fn;
  Record &out;
  const solver::Numbering<ValueTag> &numbering;
  // The match whose results are being read, and its side: a match's
  // results are visited one after another.
  Operation *lastMatch = nullptr;
  std::uint32_t lastSide = 0;
};

// The case regions around `at`, inner first, each with the constructor it
// is entered at: the one constructor the scrutinee it binds is refined to.
template <solver::FunctionNames N>
Range Reader<N>::framesAt(Operation *at) {
  Range range{static_cast<std::uint32_t>(out.frames.size()), 0};
  for (Region *region = at->getParentRegion(); region && region->getParentOp() != fn.getOperation();
       region = region->getParentRegion()) {
    auto match = dyn_cast<MatchOpInterface>(region->getParentOp());
    if (!match || region->empty() || region->front().getNumArguments() == 0)
      continue;
    auto refined = dyn_cast<DataType>(unrestricted(region->front().getArgument(0).getType()));
    if (!refined)
      continue;
    if (std::optional<Tag> tag = refined.singleTag())
      out.frames.push_back({numbering.at(match.getScrutinee()), *tag});
  }
  range.count = static_cast<std::uint32_t>(out.frames.size()) - range.first;
  return range;
}

// A match's regions, read once at its first result: each that yields to
// the match is an arm with its values; one that ends otherwise (a crash,
// a jump out of it) never gives the match its results; an empty default
// region never runs.
template <solver::FunctionNames N>
std::uint32_t Reader<N>::sideOf(Operation *match) {
  if (match == lastMatch)
    return lastSide;
  Range arms{static_cast<std::uint32_t>(out.arms.size()), 0};
  for (Region &region : match->getRegions()) {
    if (region.empty())
      continue;
    Operation *end = region.front().getTerminator();
    if (isa<RegionBranchTerminatorOpInterface>(end))
      out.arms.push_back(Yields{push(end->getOperands()), framesAt(end)});
    else
      out.arms.push_back(NeverReturns{});
  }
  arms.count = static_cast<std::uint32_t>(out.arms.size()) - arms.first;
  lastMatch = match;
  lastSide = static_cast<std::uint32_t>(out.sides.size());
  out.sides.push_back(arms);
  return lastSide;
}

// What a result is built of, where idr::sourceOf found it made here: the
// closed set of constructs this question reads, each through its own op.
template <solver::FunctionNames N>
Build Reader<N>::ofResult(OpResult result) {
  Operation *op = result.getOwner();
  if (auto call = dyn_cast<CallOp>(op)) {
    auto at = static_cast<std::uint32_t>(out.calls.size());
    if (result.getResultNumber() == 0)
      out.calls.push_back({names.id(call.getCalleeAttr()), push(call.getArgs())});
    else
      at -= 1;
    return build::Result{at, result.getResultNumber(), result.getType()};
  }
  if (isa<MatchOpInterface>(op))
    return build::Join{sideOf(op), result.getResultNumber()};
  if (auto con = dyn_cast<DataConOp>(op))
    return build::Con{con.getTag(), result.getType(), push(con.getFields()), framesAt(op)};
  if (auto pred = dyn_cast<NatPredOp>(op))
    return build::Pred{numbering.at(pred.getValue())};
  if (auto add = dyn_cast<BigAddOp>(op)) {
    Value rest = isOne(add.getRhs()) ? add.getLhs() : isOne(add.getLhs()) ? add.getRhs() : Value();
    if (rest)
      return build::Successor{numbering.at(rest)};
    return build::Opaque{};
  }
  Attribute constant;
  if (matchPattern(result, m_Constant(&constant)))
    return build::Constant{constant, result.getType(), fieldlessTag(constant, result.getType())};
  return build::Opaque{};
}

template <solver::FunctionNames N>
Build Reader<N>::buildOf(Value value) {
  if (auto arg = dyn_cast<BlockArgument>(value); arg && arg.getOwner() == &fn.getBody().front())
    return build::Entry{arg.getArgNumber()};
  return std::visit(
      llvm::makeVisitor(
          [&](const idr::Same &same) -> Build { return build::Same{numbering.at(same.value)}; },
          // A read whose op does more than compute (a memo cell's state,
          // which forcing writes) is no part of anything.
          [&](const idr::Field &field) -> Build {
            if (Operation *op = value.getDefiningOp(); op && !isMemoryEffectFree(op))
              return build::Opaque{};
            return build::Read{numbering.at(field.scrutinee), Field{field.tag, field.index},
                               value.getType()};
          },
          [&](const idr::Made &) -> Build {
            if (auto result = dyn_cast<OpResult>(value))
              return ofResult(result);
            return build::Opaque{};
          }),
      sourceOf(value));
}

// Every return of the function, with the case regions around it. A body
// whose only end is a crash has none, and gives back anything.
template <solver::FunctionNames N>
void Reader<N>::readReturns() {
  fn.getBody().walk([&](Operation *op) {
    if (!op->hasTrait<OpTrait::ReturnLike>() || isa<RegionBranchTerminatorOpInterface>(op))
      return;
    out.returns.push_back({push(op->getOperands()), framesAt(op)});
  });
}

} // namespace

template <solver::FunctionNames N>
Record readRecord(const N &names, const solver::Member &member) {
  FuncOp fn = member.fn;
  solver::Numbering<ValueTag> numbering(fn);
  Record out{member.id, numbering.size(), IndexVector<ValueId, Build>(numbering.size(), build::Opaque{}),
             {}, {}, {}, {}, {}, {}, {}, {}};
  for (Type type : fn.getArgumentTypes())
    out.argumentTypes.push_back(unrestricted(type));
  for (Type type : fn.getResultTypes())
    out.resultTypes.push_back(unrestricted(type));
  Reader<N> reader(names, fn, out, numbering);
  solver::inWalkOrder(fn, [&](Value value) { out.builds[numbering.at(value)] = reader.buildOf(value); });
  reader.readReturns();
  return out;
}

template Record readRecord<solver::ProgramGraph>(const solver::ProgramGraph &,
                                                 const solver::Member &);
template Record readRecord<solver::Editor>(const solver::Editor &, const solver::Member &);

} // namespace idr::identities
