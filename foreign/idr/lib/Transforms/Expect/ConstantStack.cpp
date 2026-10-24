// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// constant-stack: no recursion grows the native stack, stated as a property
// of the graph of references, not as the ops that happen to show it: every
// recursion is a loop, a frame pushed on a frame stack, or guaranteed tail
// calls. The contracts check it of every compilation, once the pipeline has
// ended; it follows symbol uses, whatever ops make them.

#include "idr/Transforms/Expect.h"

#include "mlir/Dialect/LLVMIR/LLVMDialect.h"
#include "llvm/ADT/SmallVectorExtras.h"

#include <cstdint>
#include <optional>

using namespace mlir;

namespace idr::expect {

namespace {

// How a function refers to another: by a guaranteed tail call, which
// replaces its frame; by any other call, which keeps it; or by a closure or
// an address that names it, which a call through the value keeps a frame
// for too.
enum class Through : std::uint8_t { GuaranteedTailCall, Call, Name };

using Node = WalkNumbering::Node;

struct Reference {
  Node target;
  Through through;
};

// The functions the body of each function refers to, read once per
// function, each function's row at its id. What the function's own
// attributes name (the clone it is) is provenance, not a call; a symbol of
// something other than a function (a global) is no reference to one.
class Graph {
public:
  Graph(const WalkNumbering &numbering, SymbolTable &symbols)
      : numbering(numbering), symbols(symbols), rows(numbering.size()) {}

  // The answer lives in its row, so it holds until the next question.
  ArrayRef<Reference> of(Node fn) {
    std::optional<SmallVector<Reference>> &row = rows[fn];
    if (row)
      return *row;
    SmallVector<Reference> &out = row.emplace();
    Region &body = numbering.op(fn).getFunctionBody();
    if (std::optional<SymbolTable::UseRange> uses = SymbolTable::getSymbolUses(&body))
      for (const SymbolTable::SymbolUse &use : *uses)
        if (auto target =
                symbols.lookup<FunctionOpInterface>(use.getSymbolRef().getRootReference()))
          out.push_back({numbering.id(target), throughOf(use.getUser())});
    return out;
  }

  SmallVector<Node> targets(Node fn) {
    return llvm::map_to_vector(of(fn), [](Reference ref) { return ref.target; });
  }

private:
  static Through throughOf(Operation *user) {
    auto call = dyn_cast<LLVM::CallOp>(user);
    if (!call)
      return isa<CallOpInterface>(user) ? Through::Call : Through::Name;
    return call.getTailCallKind() == LLVM::tailcallkind::TailCallKind::MustTail
               ? Through::GuaranteedTailCall
               : Through::Call;
  }

  const WalkNumbering &numbering;
  SymbolTable &symbols;
  IndexVector<Node, std::optional<SmallVector<Reference>>> rows;
};

} // namespace

// No recursion reachable from the function the argument names grows the
// stack: each function it may call, itself included, that is on a cycle
// of references refers to the others of its cycle only by guaranteed tail
// calls (`musttail`), each of which replaces its caller's frame. Functions
// without a body in the module call nothing back.
LogicalResult constantStack(const Request<Functions> &request) {
  SymbolTable &symbols = symbolsOf(request.module, request.analyses);
  const WalkNumbering &numbering = walkOf(request.module, request.analyses);
  // Every function the named ones may call, themselves included, each taken
  // once.
  Graph graph(numbering, symbols);
  SmallVector<Node> roots = idsOf(numbering, request.argument.functions);
  auto edges = [&](Node fn) { return graph.targets(fn); };
  // The cycle each function is on, by its id: cycles are disjoint, so one
  // table answers whether a reference stays in its caller's cycle.
  IndexVector<Node, std::optional<std::uint32_t>> cycleOf(numbering.size());
  SmallVector<SmallVector<Node>> found =
      cycles(numbering, reachable(numbering, roots, edges), edges);
  for (auto [k, cycle] : llvm::enumerate(found))
    for (Node fn : cycle)
      cycleOf[fn] = static_cast<std::uint32_t>(k);
  bool held = true;
  for (auto [k, cycle] : llvm::enumerate(found)) {
    bool grows = false;
    for (Node fn : cycle)
      for (Reference ref : graph.of(fn))
        grows |= cycleOf[ref.target] == static_cast<std::uint32_t>(k) &&
                 ref.through != Through::GuaranteedTailCall;
    if (!grows)
      continue;
    InFlightDiagnostic error = fail(numbering.op(cycle.front())->getLoc(), request.property)
                               << "the stack grows with the recursion of";
    for (Node fn : cycle)
      error << " " << where(numbering.op(fn));
    held = false;
  }
  return success(held);
}

} // namespace idr::expect
