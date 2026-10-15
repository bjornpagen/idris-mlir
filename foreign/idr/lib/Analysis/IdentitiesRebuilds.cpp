// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// Whether a function gives back one of its arguments, under what is
// assumed of the calls it makes, read off the record of its one walk.
//
// A call may rely on an assumption when it passes a part strictly below
// the argument, or when its callee's effects say it returns (it reaches
// nothing Idris did not prove total). Then every chain of calls that rely
// on one ends: it descends through values, which are finite, until it
// enters a callee that returns, inside which every chain is finite. So by
// induction on the calls a call makes, every call that relies on an
// assumption returns, does nothing else, and gives back what it was
// passed.
//
// A reading is made afresh for each question and holds what it learns
// while it answers: the part each value is, and the parts it meets. The
// record it reads is never written.
#include "idr/Analysis/Identities.h"

#include "idr/IR/Grades.h"
#include "idr/IR/IdrDialect.h"
#include "idr/IR/Symbols.h"

#include "llvm/ADT/DenseMap.h"
#include "llvm/ADT/STLExtras.h"
#include "llvm/ADT/STLForwardCompat.h"

#include <cassert>
#include <tuple>

using namespace mlir;

namespace idr::identities {

namespace {

// A part of an argument, by its number among the parts met: the argument
// itself, and what the matches and reads of the function take out of it.
// A part is a path from the argument, each step a field of a constructor
// or the predecessor of a natural (the field of its successor, as Idris
// shapes a natural). Two values that take the same path are the same part,
// however each was read: values never change, so a constructor rebuilt
// from the fields one match bound is as good as one rebuilt from another
// read of the same part.
enum class PartId : unsigned {};
// The argument itself.
constexpr PartId whole{0};

// A part's depth, its steps below the argument, is what makes a recursion
// on parts end: each step is a strictly smaller value, and a value is
// finite. Its type is at no grade.
struct Part {
  unsigned depth;
  Type type;
};

// The parts of one argument met so far, each once.
class Parts {
public:
  explicit Parts(Type argument) { parts.push_back({0, argument}); }
  const Part &operator[](PartId part) const { return parts[llvm::to_underlying(part)]; }
  // Field `index`, of type `type`, of the part `parent` built by the
  // constructor of tag `tag`.
  PartId field(PartId parent, Tag tag, unsigned index, Type type) {
    return step(parent, tag, index, type);
  }
  // The predecessor of the natural `parent`, which is not zero.
  PartId predecessor(PartId parent) {
    return step(parent, std::nullopt, 0, (*this)[parent].type);
  }

private:
  // The field's constructor, by its tag in its data type; none for the
  // predecessor of a natural.
  PartId step(PartId parent, std::optional<Tag> tag, unsigned index, Type type) {
    auto [it, made] = steps.try_emplace(std::make_tuple(parent, tag, index),
                                        PartId(static_cast<unsigned>(parts.size())));
    if (made)
      parts.push_back(Part{(*this)[parent].depth + 1, unrestricted(type)});
    return it->second;
  }

  SmallVector<Part> parts;
  llvm::DenseMap<std::tuple<PartId, std::optional<Tag>, unsigned>, PartId> steps;
};

} // namespace

class Record::Reading {
public:
  Reading(const Record &record, const Assumed &assumed)
      : record(record), assumed(assumed), memo(record.nodes.size()) {
    for (Type type : record.types)
      parts.emplace_back(type);
  }

  // Whether the walk gives back the candidate of `slot`: every call it
  // relies on gives back a part of it, and every return rebuilds it.
  bool givesBack(unsigned slot) {
    for (Id call : record.reliant)
      if (!partOf(call, slot))
        return false;
    return llvm::all_of(record.rets, [&](const Ret &ret) {
      return rebuilds(ret.value, whole, ret.frames, slot);
    });
  }

private:
  // The part each candidate's slot finds a value to be, if any.
  using Held = SmallVector<std::optional<PartId>, 1>;

  const Held &fill(Id node);
  std::optional<PartId> partOf(Id node, unsigned slot) { return fill(node)[slot]; }
  std::optional<Fact> knownAt(PartId part, ArrayRef<Frame> frames, unsigned slot);
  bool rebuilds(Id node, PartId part, ArrayRef<Frame> frames, unsigned slot);
  bool rebuildsCon(const Con &con, PartId part, ArrayRef<Frame> frames, unsigned slot);
  bool rebuildsSuccessor(const Successor &successor, PartId part, ArrayRef<Frame> frames,
                         unsigned slot);
  bool rebuildsJoin(const Join &join, PartId part, unsigned slot);
  bool rebuildsConstant(const Constant &constant, PartId part, ArrayRef<Frame> frames,
                        unsigned slot);

  const Record &record;
  const Assumed &assumed;
  SmallVector<Parts, 1> parts;
  // Each value's parts, filled the first time it is asked for.
  std::vector<std::optional<Held>> memo;
};

// The parts of every slot at once. A call gives back the part its callee is
// assumed to give back when it may rely on the assumption: the part is
// strictly below the argument, or the callee returns.
const Record::Reading::Held &Record::Reading::fill(Id node) {
  std::optional<Held> &slotOf = memo[llvm::to_underlying(node)];
  if (slotOf)
    return *slotOf;
  auto width = static_cast<unsigned>(record.arguments.size());
  Held held(width, std::nullopt);
  auto each = [&](Id of, auto step) {
    const Held &from = fill(of);
    for (unsigned slot = 0; slot < width; ++slot)
      if (std::optional<PartId> part = from[slot])
        held[slot] = step(slot, *part);
  };
  std::visit(
      llvm::makeVisitor(
          [](const Opaque &) {}, [](const Con &) {}, [](const Successor &) {},
          [](const Join &) {}, [](const Constant &) {},
          [&](const Entry &entry) {
            if (auto it = record.slots.find(entry.arg); it != record.slots.end())
              held[it->second] = whole;
          },
          [&](const Same &same) { held = fill(same.of); },
          [&](const Field &field) {
            each(field.of, [&](unsigned slot, PartId part) {
              return parts[slot].field(part, field.tag, field.index, field.type);
            });
          },
          [&](const Pred &pred) {
            each(pred.of,
                 [&](unsigned slot, PartId part) { return parts[slot].predecessor(part); });
          },
          [&](const Call &call) {
            auto entry = assumed.find(call.callee);
            if (entry == assumed.end())
              return;
            // An assumption names a parameter of the callee, and every call
            // passes one argument per parameter: the verifier's on the
            // input, kept by inlining, building and redirect.
            for (unsigned slot = 0; slot < width; ++slot)
              for (unsigned param : entry->second) {
                assert(param < call.args.size() && "a call passes every parameter");
                std::optional<PartId> part = fill(call.args[param])[slot];
                if (part && (call.returns || parts[slot][*part].depth > 0)) {
                  held[slot] = part;
                  break;
                }
              }
          }),
      record.build(node));
  // The memo is sized once, so the recursion above moved no slot.
  slotOf = std::move(held);
  return *slotOf;
}

// What the matches around a use say `part` is, inner first, or else the
// one constructor its type has.
std::optional<Record::Fact> Record::Reading::knownAt(PartId part, ArrayRef<Frame> frames,
                                                     unsigned slot) {
  for (const Frame &frame : frames)
    if (partOf(frame.scrutinee, slot) == part)
      return frame.fact;
  DataType data = dataTypeOf(parts[slot][part].type);
  if (data && data.getCtors().size() == 1)
    return Fact{KnownTag{Tag{0}}};
  return std::nullopt;
}

bool Record::Reading::rebuilds(Id node, PartId part, ArrayRef<Frame> frames, unsigned slot) {
  if (partOf(node, slot) == part)
    return true;
  return std::visit(
      llvm::makeVisitor(
          [](const Opaque &) { return false; }, [](const Entry &) { return false; },
          [](const Field &) { return false; }, [](const Pred &) { return false; },
          [](const Call &) { return false; },
          [&](const Same &same) { return rebuilds(same.of, part, frames, slot); },
          [&](const Con &con) { return rebuildsCon(con, part, frames, slot); },
          [&](const Successor &successor) {
            return rebuildsSuccessor(successor, part, frames, slot);
          },
          [&](const Join &join) { return rebuildsJoin(join, part, slot); },
          [&](const Constant &constant) {
            return rebuildsConstant(constant, part, frames, slot);
          }),
      record.build(node));
}

bool Record::Reading::rebuildsCon(const Con &con, PartId part, ArrayRef<Frame> frames,
                                  unsigned slot) {
  std::optional<Fact> known = knownAt(part, frames, slot);
  const KnownTag *tag = known ? std::get_if<KnownTag>(&*known) : nullptr;
  if (!tag || tag->tag != con.tag || unrestricted(con.type) != parts[slot][part].type)
    return false;
  for (auto [at, field] : llvm::enumerate(con.fields)) {
    PartId sub = parts[slot].field(part, con.tag, static_cast<unsigned>(at), con.types[at]);
    if (!rebuilds(field, sub, frames, slot))
      return false;
  }
  return true;
}

// `S k` is n where k is n's predecessor: n is not zero, as the predecessor
// op that k was read through shows by running at all.
bool Record::Reading::rebuildsSuccessor(const Successor &successor, PartId part,
                                        ArrayRef<Frame> frames, unsigned slot) {
  if (!isa<NatType>(parts[slot][part].type))
    return false;
  return rebuilds(successor.of, parts[slot].predecessor(part), frames, slot);
}

bool Record::Reading::rebuildsJoin(const Join &join, PartId part, unsigned slot) {
  return llvm::all_of(record.joins[join.side], [&](const Arm &arm) {
    return std::visit(llvm::makeVisitor([](const Fails &) { return false; },
                                        [](const Unreachable &) { return true; },
                                        [&](const Yields &yields) {
                                          return rebuilds(yields.values[join.result], part,
                                                          yields.frames, slot);
                                        }),
                      arm);
  });
}

bool Record::Reading::rebuildsConstant(const Constant &constant, PartId part,
                                       ArrayRef<Frame> frames, unsigned slot) {
  std::optional<Fact> known = knownAt(part, frames, slot);
  if (!known)
    return false;
  return std::visit(llvm::makeVisitor(
                        [&](const KnownLiteral &literal) {
                          return constant.value == literal.literal;
                        },
                        [&](const KnownTag &tag) {
                          return constant.fieldless == tag.tag &&
                                 unrestricted(constant.type) == parts[slot][part].type;
                        }),
                    *known);
}

SmallVector<unsigned, 1> Record::givesBack(ArrayRef<unsigned> asked,
                                           const Assumed &assumed) const {
  Reading reading(*this, assumed);
  SmallVector<unsigned, 1> kept;
  for (unsigned argument : asked) {
    auto slot = slots.find(argument);
    assert(slot != slots.end() && "an assumption is about one of the walk's candidates");
    if (reading.givesBack(slot->second))
      kept.push_back(argument);
  }
  return kept;
}

} // namespace idr::identities
