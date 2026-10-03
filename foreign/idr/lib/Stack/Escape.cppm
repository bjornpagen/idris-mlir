// idr.stack:escape: escape analysis of boxes, which cells can outlive the frame that builds
// them.
//
// A reference to a cell is held by SSA values and parameters, and by the
// fields of other cells and of unboxed sums. Within a function the analysis
// follows it through a graph of nodes, each a value in one of two modes: a
// box value stands for the reference it holds (shallow), or for everything
// reachable from it through fields, its own reference too (deep). An
// unboxed sum has no reference of its own, so its only node is deep. The
// edges:
//   - a value to the values MLIR says it is forwarded to (the successor
//     inputs of a region branch: a match's result for a yield, an
//     scf.while's arguments and results for its initial values and its
//     terminators' operands), to an arith.select's result, and into and out
//     of a linear type (idr.lin.enter, idr.lin.use), in the same mode:
//     linearity has no runtime form, and a value used once may still be
//     used where it escapes;
//   - a deep value to what reading it gives (idr.field, the arguments of a
//     match's case regions), deep, and a deep box to its own reference;
//   - a value stored in a constructor to the constructor's value, deep.
// A node escapes when it reaches a use that lets it go: a return, a
// closure's capture, an idr.apply, a call of a function without a body or
// of a parameter whose node escapes, or any op this analysis does not know.
// Reading a box (idr.field, idr.tag, a match's scrutinee) lets nothing go.
//
// A parameter's nodes are summarized over the module's calls as the least
// solution, so a parameter a function only passes to itself does not escape
// through that call. A cell passed to a parameter whose node does not escape
// is live only while the call runs, inside the caller's frame.
//
// The cell an idr.con builds lives in one stack slot per con, in its
// function's entry block. So it also escapes when the con may run again in
// the same frame while the cell is live: the cell must not be forwarded by
// a terminator of a loop around the con, which carries values to the next
// iteration or out of the loop. Nor may it be passed to a call in tail
// position of a function on the same cycle of calls: such a call must be a
// tail call (idr-tail-calls) for the cycle to run in constant stack, or
// the next iteration of a loop (idr-tail-loops) when it is a self call, and
// either way the frame is gone when the callee runs. A function off the
// cycle never calls back round to this frame's function, so a call of it in
// tail position may stay a call that keeps the frame: idr-tail-calls leaves
// a call that takes its caller's frame a call. A con
// counts only in a function body of one block whose regions on the way are
// those of matches (at most one runs, once) and of scf.while (one
// iteration at a time); anywhere else it escapes.
export module idr.stack:escape;

import idr.mlir;
import idr.dialect;
import idr.graph;

import :recursion;

using namespace mlir;

export namespace idr::stack {

class Escapes {
public:
  // Computes the summaries of every parameter of the module's functions,
  // whose cycles of calls are `cycles`.
  Escapes(mlir::ModuleOp module, const Cycles &cycles);

  // Whether the cell that `con`, a box's constructor, builds may outlive its
  // frame, or be live when `con` runs again in the same frame.
  bool mayEscape(ConOp con);

  enum class Mode : uint8_t { Shallow, Deep };
  using Node = std::pair<mlir::Value, Mode>;
  // The node of `value` in `mode`; a sum's only node is deep.
  static Node node(mlir::Value value, Mode mode);

private:
  // Where the nodes of a function are followed: `repeating` are the ops
  // that may run a con again in the same frame (its loops, and the function
  // itself, whose calls in tail position end the frame); none, for the
  // function's parameters, whose cells outlive the calls.
  struct Frame {
    mlir::func::FuncOp fn;
    llvm::ArrayRef<mlir::Operation *> repeating;
  };

  // Where a use sends a node: to other nodes (none for a read), or nowhere
  // this analysis can follow (nullopt), which is an escape.
  using Flow = std::optional<llvm::SmallVector<Node, 2>>;

  // The nodes of the frame's function that escape.
  llvm::DenseSet<Node> escaping(const Frame &frame) const;
  Flow flow(mlir::OpOperand &use, Mode mode, const Frame &frame,
            const mlir::RegionBranchSuccessorMapping &forwards) const;

  mlir::ModuleOp module;
  mlir::SymbolTable symbols;
  const Cycles &cycles;
  // The nodes of parameters that escape.
  llvm::DenseSet<Node> parameters;
  // The escaping nodes of a function around the cons of one innermost loop
  // (null for none), once the summaries are final.
  llvm::DenseMap<std::pair<mlir::Operation *, mlir::Operation *>, llvm::DenseSet<Node>> cache;
};

} // namespace idr::stack

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

Escapes::Escapes(ModuleOp top, const Cycles &cycles) : module(top), symbols(top), cycles(cycles) {
  SmallVector<func::FuncOp> fns;
  for (auto fn : module.getOps<func::FuncOp>())
    if (!fn.isExternal())
      fns.push_back(fn);
  // The functions whose summaries depend on each function's: its callers.
  // PIN(clang-module-layout-forward-declaration) — see PINS.md
  DenseMap<Operation *, SetVector<func::FuncOp>> callers;
  for (func::FuncOp fn : fns)
    fn.walk([&](func::CallOp call) {
      if (auto callee = symbols.lookup<func::FuncOp>(call.getCalleeAttr().getAttr()))
        callers[callee].insert(fn);
    });
  // Parameters only ever join the escaping ones, so the worklist ends with
  // the least solution.
  SetVector<func::FuncOp> work;
  for (func::FuncOp fn : llvm::reverse(fns))
    work.insert(fn);
  while (!work.empty()) {
    func::FuncOp fn = work.pop_back_val();
    DenseSet<Node> escapes = escaping({fn, {}});
    bool changed = false;
    for (BlockArgument param : fn.getArguments())
      for (Mode mode : {Mode::Shallow, Mode::Deep})
        if (Node n = node(param, mode); escapes.contains(n))
          changed |= parameters.insert(n).second;
    if (changed)
      for (func::FuncOp caller : callers.lookup(fn))
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
      // arguments are the fields. A match on a linear value takes it
      // apart, and the cell it leaves is the match's to build in again: the
      // cell's own reference goes with it.
      .Case([&](MatchOp match) -> Flow {
        if (mode == Mode::Shallow && quantityOf(match.getScrutinee().getType()) == Quantity::One)
          return lost;
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
        // A call in tail position on the frame's cycle is a tail call
        // (idr-tail-calls), and a self one the next iteration of a loop
        // (idr-tail-loops): either way the frame that built the cell is
        // gone when the callee runs. A parameter's cell is another
        // frame's, which outlives the call.
        if (!frame.repeating.empty() && graph::inTailPosition(call) &&
            cycles.together(frame.fn, callee))
          return lost;
        if (parameters.contains(node(callee.getArgument(use.getOperandNumber()), mode)))
          return lost;
        return SmallVector<Node, 2>();
      })
      .Default([](Operation *) -> Flow { return lost; });
}

} // namespace idr::stack
