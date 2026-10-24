// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// What the units of exclusivity's solve share, and no other unit reads:
// ExclusivityGraph.cpp reads each body once into a Body, ExclusivityAnalyses.cpp
// solves the program by context over those bodies, and Exclusivity.cpp keeps
// the answer. A body's values are its followed values in the walk's order
// (exclusivity::forEachFollowed), so every number here is a position, and
// no table is keyed by an IR pointer.
//
// The solve marks "shared": a value is exclusive until a path shares it,
// optimistic as SCCP is and sound by induction on the run. What shares a
// value: a reference taken from it or from a view of it (a copy of a value
// read, which a dup is), a parameter its context does not take exclusive,
// a value no declared flow explains, a constant, and whatever a shared
// value moves into or out of. In a context every followed parameter the
// context takes exclusive is exclusive, so no edge runs from an argument
// to a parameter: a call goes to the context of the parameters it passes
// exclusive values at, and only a callee's returns flow back.
#ifndef IDR_ANALYSIS_OWNERSHIP_EXCLUSIVITYDETAIL_H
#define IDR_ANALYSIS_OWNERSHIP_EXCLUSIVITYDETAIL_H

#include "idr/Analysis/Ownership.h"
#include "idr/Analysis/Solver/ProgramGraph.h"
#include "idr/IR/IdrDialect.h"
#include "idr/Support/Footprint.h"
#include "idr/Support/Id.h"

#include "llvm/ADT/SmallBitVector.h"
#include "llvm/ADT/SmallVector.h"

#include <cstdint>
#include <optional>
#include <tuple>
#include <variant>

namespace idr::detail::exclusivity {

using solver::FunctionId;

// A followed value of one body, by its position in the walk.
using Local = std::uint32_t;
inline constexpr Local noLocal = ~Local{0};

// shared(from) gives shared(to), within one body.
struct Edge {
  Local from;
  Local to;
};

// Where a view a body passes on was lent from: a followed value of the
// body, or the body's own parameter `index`, itself a view.
struct ViewRoot {
  enum class Kind : std::uint8_t { Value, Parameter } kind;
  std::uint32_t index;
};

// A field of a memo label, the one place every cell of the label holds that
// capture: an init moves a value into it and a force moves it out, through
// whatever the cell passed between. Numbered across the program.
using Anchor = std::uint32_t;

struct Call {
  FunctionId callee;
  // The local of each argument, by the callee's parameter position;
  // noLocal where the parameter is not followed.
  llvm::SmallVector<Local, 4> args;
  // The local of each result; noLocal where it is not followed.
  llvm::SmallVector<Local, 2> results;
  // Each view argument's root, by parameter position, for the views a
  // callee takes a reference of.
  llvm::SmallVector<std::pair<unsigned, ViewRoot>, 2> views;
};

// What the type of a value the solve does not follow says of it: exclusive
// where it reaches no cell or its grade claims all it reaches unshared,
// shared otherwise.
enum class ByType : std::uint8_t { Shared, Exclusive };

// What a body gives back at one result: a followed value, whose sharing the
// solve decides, or a value it does not follow, whose type answers.
using Returned = std::variant<Local, ByType>;

// One function's body, read once. Its lists are sized by the body, in the
// containers a pass's footprint counts.
struct Body {
  FuncOp fn;
  std::uint32_t values = 0;
  // The local of each parameter, by position; noLocal where it is not
  // followed.
  llvm::SmallVector<Local, 4> params;
  // What each operand of the body's return gives back, by result position;
  // none for a body that never returns.
  std::optional<llvm::SmallVector<Returned, 2>> returns;
  footprint::Vector<Edge> edges;
  // Values shared in every context: copies, constants, values no flow
  // explains, inputs no predecessor forwards, region arguments no
  // interface says.
  footprint::Vector<Local> seeds;
  // Views a reference is taken of here, by root.
  footprint::Vector<ViewRoot> viewsCopied;
  footprint::Vector<Call> calls;
  // Moves into memo labels' fields, and the parts moved or read out of
  // them, each holding what its field holds.
  footprint::Vector<std::pair<Local, Anchor>> intoAnchors;
  footprint::Vector<std::pair<Anchor, Local>> outOfAnchors;
};

// The memo labels' fields of a program and the ones static data or a read
// that keeps a second reference shares whatever an init moves in.
class Anchors {
public:
  Anchor of(const FlowAnchor::Field &field);
  void share(Anchor anchor) { sharedAnchors.push_back(anchor); }
  std::uint32_t size() const { return static_cast<std::uint32_t>(keys.size()); }
  llvm::ArrayRef<Anchor> shared() const { return sharedAnchors; }

private:
  // A field by its declaration's identity: its family, uniqued by content,
  // its member and its positions, so a field named at generic levels and at
  // an instance is one anchor; no IR node is a key. Sized by the program's
  // memo fields, so held in the footprint's storage.
  using Key = std::tuple<mlir::Attribute, std::uint32_t, std::uint32_t, std::uint32_t>;
  footprint::DenseMap<Key, Anchor> keys;
  footprint::Vector<Anchor> sharedAnchors;
};

// Reads `fn`'s body, the functions it calls resolved through `graph`, its
// memo fields numbered in `anchors`. A terminator with block successors,
// which no body holds before the lowering, is a fatal internal error at
// the op.
Body readBody(FuncOp fn, const solver::ProgramGraph &graph, Anchors &anchors);

// The static data of `program` that holds a memo label: its fields are
// static, and shared whatever an init moves in.
void shareStaticAnchors(ProgramOp program, Anchors &anchors);

// The parameters of each body a reference is taken of through a view
// rooted at them, here or in a callee: one bit per parameter position.
IndexVector<FunctionId, llvm::SmallBitVector>
copiedViews(const IndexVector<FunctionId, Body> &bodies,
            const solver::ProgramGraph &graph);

// The answer of the solve: the versions of each function, and what it
// measured, its work the nodes and edges of every round's marking.
struct Solution {
  IndexVector<FunctionId, footprint::Vector<Exclusivity::Version>> versions;
  unsigned contexts = 0;
  unsigned copies = 0;
  unsigned rounds = 0;
  std::uint64_t work = 0;
};

// The solve by context over the program's bodies, its copied views and its
// anchors.
Solution solve(const IndexVector<FunctionId, Body> &bodies,
               const IndexVector<FunctionId, llvm::SmallBitVector> &copied,
               const Anchors &anchors, const solver::ProgramGraph &graph);

} // namespace idr::detail::exclusivity

#endif // IDR_ANALYSIS_OWNERSHIP_EXCLUSIVITYDETAIL_H
