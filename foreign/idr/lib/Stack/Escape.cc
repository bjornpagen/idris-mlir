// Escape analysis of boxes (Stack/Escape.h).

#include "Stack/Escape.h"

#include "Stack/Tail.h"

#include "llvm/ADT/SetVector.h"
#include "llvm/ADT/TypeSwitch.h"

using namespace mlir;

namespace idr::stack {

namespace {

using Mode = Escapes::Mode;

// A use that sends a reference where the analysis cannot follow it.
constexpr std::nullopt_t lost = std::nullopt;

// A type as it is at runtime: linearity has no runtime form.
Type runtimeType(Type type) { return unrestricted(type); }

// The values whose references the analysis follows: boxes, and unboxed
// sums, whose fields may hold boxes.
bool holdsCells(Type type) { return isa<BoxType, DataType>(runtimeType(type)); }

// The ops around `con` that may run it again in its frame, innermost first:
// its loops, then its function. Nothing when the con is somewhere else than
// in regions of matches and loops of one block each, in a function of
// `module`.
std::optional<SmallVector<Operation *>> repeating(ConOp con, ModuleOp module) {
  SmallVector<Operation *> around;
  for (Operation *op = con;; op = op->getParentOp()) {
    Region *region = op->getParentRegion();
    if (!region || !region->hasOneBlock())
      return std::nullopt;
    Operation *parent = region->getParentOp();
    if (isa<func::FuncOp>(parent) && parent->getParentOp() == module) {
      around.push_back(parent);
      return around;
    }
    if (isa<scf::WhileOp>(parent))
      around.push_back(parent);
    else if (!isa<MatchOp, MatchLitOp>(parent))
      return std::nullopt;
  }
}

// Every operand of `fn` that a region branch forwards, and the values it
// goes to.
RegionBranchSuccessorMapping forwardsOf(func::FuncOp fn) {
  RegionBranchSuccessorMapping forwards;
  fn->walk([&](RegionBranchOpInterface branch) {
    branch.getSuccessorOperandInputMapping(forwards);
  });
  return forwards;
}

} // namespace

Escapes::Node Escapes::node(Value value, Mode mode) {
  return {value, isa<BoxType>(runtimeType(value.getType())) ? mode : Mode::Deep};
}

Escapes::Escapes(ModuleOp top) : module(top), symbols(top) {
  SmallVector<func::FuncOp> fns;
  for (auto fn : module.getOps<func::FuncOp>())
    if (!fn.isExternal())
      fns.push_back(fn);
  // The functions whose summaries depend on each function's: its callers.
  DenseMap<Operation *, SetVector<Operation *>> callers;
  for (func::FuncOp fn : fns)
    fn.walk([&](func::CallOp call) {
      if (auto callee = symbols.lookup<func::FuncOp>(call.getCalleeAttr().getAttr()))
        callers[callee].insert(fn);
    });
  // Parameters only ever join the escaping ones, so the worklist ends with
  // the least solution.
  SetVector<Operation *> work;
  for (func::FuncOp fn : llvm::reverse(fns))
    work.insert(fn);
  while (!work.empty()) {
    auto fn = cast<func::FuncOp>(work.pop_back_val());
    DenseSet<Node> escapes = escaping({fn, {}});
    bool changed = false;
    for (BlockArgument param : fn.getArguments())
      for (Mode mode : {Mode::Shallow, Mode::Deep})
        if (Node n = node(param, mode); escapes.contains(n))
          changed |= parameters.insert(n).second;
    if (changed)
      for (Operation *caller : callers.lookup(fn))
        work.insert(caller);
  }
}

bool Escapes::mayEscape(ConOp con) {
  std::optional<SmallVector<Operation *>> around = repeating(con, module);
  if (!around)
    return true;
  auto key = std::make_pair(around->back(), around->front());
  auto it = cache.find(key);
  if (it == cache.end())
    it = cache.try_emplace(key, escaping({cast<func::FuncOp>(around->back()), *around})).first;
  return it->second.contains(node(con.getResult(), Mode::Shallow));
}

DenseSet<Escapes::Node> Escapes::escaping(const Frame &frame) const {
  RegionBranchSuccessorMapping forwards = forwardsOf(frame.fn);
  // The graph reversed: the nodes that lead to each node.
  DenseMap<Node, SmallVector<Node>> into;
  DenseSet<Node> escapes;
  SmallVector<Node> work;
  auto visit = [&](Value value) {
    if (!holdsCells(value.getType()))
      return;
    // Everything reachable from a value includes its own reference.
    into[node(value, Mode::Shallow)].push_back(node(value, Mode::Deep));
    for (Mode mode : {Mode::Shallow, Mode::Deep}) {
      Node from = node(value, mode);
      bool escape = llvm::any_of(value.getUses(), [&](OpOperand &use) {
        Flow to = flow(use, from.second, frame, forwards);
        for (Node next : to.value_or(SmallVector<Node, 2>()))
          into[next].push_back(from);
        return !to;
      });
      if (escape && escapes.insert(from).second)
        work.push_back(from);
    }
  };
  Operation *fn = frame.fn;
  fn->walk([&](Block *block) {
    for (BlockArgument arg : block->getArguments())
      visit(arg);
  });
  fn->walk([&](Operation *op) {
    for (Value result : op->getResults())
      visit(result);
  });
  // Whatever leads to a node that escapes escapes too.
  while (!work.empty())
    for (Node from : into.lookup(work.pop_back_val()))
      if (escapes.insert(from).second)
        work.push_back(from);
  return escapes;
}

Escapes::Flow Escapes::flow(OpOperand &use, Mode mode, const Frame &frame,
                            const RegionBranchSuccessorMapping &forwards) const {
  Operation *user = use.getOwner();
  if (auto it = forwards.find(&use); it != forwards.end()) {
    // A terminator of a loop around the con carries the cell into the
    // loop's next iteration, where the con writes its slot again.
    if (isa<RegionBranchTerminatorOpInterface>(user) &&
        llvm::is_contained(frame.repeating, user->getParentOp()))
      return lost;
    return llvm::map_to_vector<2>(it->second, [&](Value to) { return node(to, mode); });
  }
  // Reading a cell lets nothing go; what it reads is reachable from it.
  auto read = [&](ValueRange values) -> Flow {
    if (mode == Mode::Shallow)
      return SmallVector<Node, 2>();
    return llvm::map_to_vector<2>(values, [&](Value to) { return node(to, Mode::Deep); });
  };
  return TypeSwitch<Operation *, Flow>(user)
      .Case([&](FieldOp field) { return read(field.getResult()); })
      .Case([&](TagOp) { return read({}); })
      // A match's only operand is its scrutinee; its case regions'
      // arguments are the fields.
      .Case([&](MatchOp match) {
        SmallVector<Value> fields;
        for (Region &region : match.getRegions())
          llvm::append_range(fields, region.getArguments());
        return read(fields);
      })
      .Case([&](ConOp con) -> Flow { return SmallVector<Node, 2>{node(con, Mode::Deep)}; })
      // A select, and a move into or out of a linear type, pass the
      // reference on unchanged.
      .Case<arith::SelectOp, LinEnterOp, LinUseOp>([&](Operation *op) -> Flow {
        return SmallVector<Node, 2>{node(op->getResult(0), mode)};
      })
      .Case([&](func::CallOp call) -> Flow {
        auto callee = symbols.lookup<func::FuncOp>(call.getCalleeAttr().getAttr());
        if (!callee || callee.isExternal())
          return lost;
        // A self tail call becomes the next iteration of a loop.
        if (callee == frame.fn && llvm::is_contained(frame.repeating, callee.getOperation()) &&
            inTailPosition(call))
          return lost;
        if (parameters.contains(node(callee.getArgument(use.getOperandNumber()), mode)))
          return lost;
        return SmallVector<Node, 2>();
      })
      .Default([](Operation *) -> Flow { return lost; });
}

} // namespace idr::stack
