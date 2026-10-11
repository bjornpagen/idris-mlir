// idr.identity:rebuilds: whether a function gives back one of its
// arguments, under what is assumed of the calls it makes.
//
// A return gives back the argument x when its value is x rebuilt: x
// itself, or a part of x where x is that part (see parts); a constructor
// where x is known to be that constructor, each field that holds something
// at runtime the same field of x rebuilt (an erased field holds nothing,
// and nothing can tell one erased value from another); a constant where x
// is known to be that literal, or a constructor whose fields are all
// erased; the successor of x's predecessor; a match whose every region
// that returns yields x rebuilt; a value held at another quantity; or a
// call assumed to give back what it is passed, passed x. What x is known
// to be at a return is what the matches around it say (a case binds its
// constructor or its literal), or the one constructor its type has; values
// never change, so it holds of every read of x, wherever the read is.
//
// The function must also only compute: each op only allocates its results
// (a call as its callee's facts say), or is a match whose regions only
// compute, or a call assumed to give back what it is passed that it may
// rely on. A region that ends in ub.unreachable and does nothing else on
// the way is one Idris proved is never taken. In the owned stage, where a
// value holds or borrows a reference, nothing gives back anything: a
// counted value cannot stand for a fresh one.
//
// A call may rely on an assumption when it passes a part strictly below
// the argument, or when its callee's facts say it returns (it reaches
// nothing Idris did not prove total). Then every chain of calls that rely
// on one ends: it descends through values, which are finite, until it
// enters a callee that returns, inside which every chain is finite. So by
// induction on the calls a call makes, every call that relies on an
// assumption returns, does nothing else, and gives back what it was
// passed.
//
// The function is walked once to record that. The walk leaves the part
// each value is of every candidate argument, and the calls whose result is
// an operand while the callee is assumed to give that operand back.
// givesBack reads the record under whatever assumptions it is handed, so
// the arguments share one walk, and a caller requeued after an assumption
// is dropped is not walked again.
export module idr.identity:rebuilds;

import idr.mlir;
import idr.dialect;
import idr.facts;

import :parts;

using namespace mlir;
using namespace idr;

export namespace idr::identity {

// The parameters of each function, by name, assumed to be given back.
using Assumed = DenseMap<StringAttr, SmallVector<unsigned, 1>>;

// One walk of a function, for every argument it might give back. The body
// is not walked again: givesBack reads what the walk recorded.
class Rebuilds {
public:
  Rebuilds(func::FuncOp fn, ArrayRef<unsigned> candidates);

  // The subset of `asked`, in that order, that the walk gives back
  // under `assumed`. When the calls this read last consulted still stand
  // as they did, the previous answer stands with them: a requeue that
  // changed nothing those calls rely on does not read the record through
  // again.
  SmallVector<unsigned, 1> givesBack(ArrayRef<unsigned> asked, const Assumed &assumed);

private:
  // What a part is known to be where a value stands for it: built by a
  // constructor, a literal, or neither.
  struct Known {
    StringAttr ctor;
    Attribute literal;
  };

  // A match the use sits in, inner first, as knownAt walks parent regions.
  struct Frame {
    int scrutinee = -1;
    bool lit = false;
    bool named = false;
    StringAttr ctor;
    Attribute literal;
  };

  // One region of a match: empty fails, unreachable is skipped, a yield
  // must rebuild.
  struct Arm {
    bool empty = false;
    bool unreachable = false;
    bool yield = false;
    SmallVector<int, 1> values;
    SmallVector<Frame, 2> frames;
  };

  // How a value is built. Calls are the only place an assumption is read;
  // everything else is fixed by the walk.
  struct Node {
    enum Kind : uint8_t {
      Dead,
      Entry,
      MatchArg,
      Copy,
      Field,
      Pred,
      Call,
      Con,
      Add,
      Join,
      Const
    } kind = Dead;

    // Entry: which function argument. MatchArg and Field: which field.
    // Join: which result.
    unsigned arg = 0;
    int src = -1;
    StringAttr ctor;
    StringAttr callee;
    Type type;
    Attribute attr;
    bool memo = false;
    bool deflt = false;
    bool returns = false;
    bool allocates = false;
    bool isCon = false;
    bool conRun = false;
    bool erased = false;
    SmallVector<int, 4> ops;
    SmallVector<Type, 4> types;
    unsigned side = 0;
  };

  struct Ret {
    int value = -1;
    SmallVector<Frame, 2> frames;
  };

  // The assumption list a read of the record consulted, copied so a later
  // drop compares unequal.
  struct Snapshot {
    StringAttr name;
    std::optional<SmallVector<unsigned, 1>> params;
  };

  struct Memo {
    unsigned epoch = 0;
    SmallVector<std::optional<unsigned>, 1> parts;
  };

  static bool owns(Type type) { return gradeOf(type).permission != Permission::Plain; }

  static bool isOne(Value value) {
    Attribute constant;
    auto big = matchPattern(value, m_Constant(&constant)) ? dyn_cast<BigAttr>(constant) : BigAttr();
    return big && big.getValue() == "1";
  }

  static StringAttr caseCtor(MatchOp match, unsigned region) {
    return cast<FlatSymbolRefAttr>(match.getCases()[region]).getAttr();
  }

  bool memoType(Type type) {
    DataOp data = lookupData(fn, type);
    return data && isMemo(data);
  }

  // The one constructor of the scrutinee's type that no case of `match`
  // names, which its default region therefore takes, if there is one.
  StringAttr remaining(MatchOp match) {
    DataOp data = lookupData(fn, match.getScrutinee().getType());
    if (!data)
      return {};
    SmallVector<CtorOp> ctors = data.getCtors();
    if (ctors.size() != match.getCases().size() + 1)
      return {};
    for (CtorOp ctor : ctors)
      if (llvm::none_of(match.getCases(), [&](Attribute named) {
            return cast<FlatSymbolRefAttr>(named).getAttr() == ctor.getSymNameAttr();
          }))
        return ctor.getSymNameAttr();
    return {};
  }

  int place(Value value, Node node) {
    int id = static_cast<int>(nodes.size());
    nodes.push_back(std::move(node));
    memo.emplace_back();
    ids[value] = id;
    return id;
  }

  int intern(Value value) {
    if (auto it = ids.find(value); it != ids.end())
      return it->second;
    if (auto arg = dyn_cast<BlockArgument>(value))
      return internArg(arg);
    return internResult(cast<OpResult>(value));
  }

  int internArg(BlockArgument arg) {
    Node node;
    Block *block = arg.getOwner();
    if (block == &fn.getBody().front()) {
      node.kind = Node::Entry;
      node.arg = arg.getArgNumber();
    } else if (auto match = dyn_cast_or_null<MatchOp>(block->getParentOp())) {
      node.kind = Node::MatchArg;
      node.src = intern(match.getScrutinee());
      node.arg = arg.getArgNumber();
      node.type = arg.getType();
      node.memo = memoType(match.getScrutinee().getType());
      unsigned region = block->getParent()->getRegionNumber();
      if (region >= match.getCases().size())
        node.deflt = true;
      else
        node.ctor = caseCtor(match, region);
    }
    return place(arg, std::move(node));
  }

  int defineCall(func::CallOp call) {
    for (Value result : call.getResults())
      if (auto it = ids.find(result); it != ids.end())
        return it->second;
    Node node;
    node.kind = Node::Call;
    node.callee = call.getCalleeAttr().getAttr();
    node.returns = !facts::of(lookupSymbol<func::FuncOp>(fn, node.callee)).diverge;
    node.allocates = onlyAllocates(call);
    for (Value operand : call.getOperands())
      node.ops.push_back(intern(operand));
    int id = static_cast<int>(nodes.size());
    nodes.push_back(std::move(node));
    memo.emplace_back();
    for (Value result : call.getResults())
      ids[result] = id;
    return id;
  }

  void encodeConst(Node &node, Value value, Attribute constant) {
    node.kind = Node::Const;
    node.attr = constant;
    node.type = value.getType();
    auto con = dyn_cast<ConAttr>(constant);
    if (!con)
      return;
    node.isCon = true;
    node.conRun = con.isRun();
    if (node.conRun)
      return;
    node.ctor = con.getCtor().getLeafReference();
    CtorOp ctor = lookupCtor(fn, con.getCtor());
    node.erased = ctor && llvm::all_of(ctor.getFieldTypes().getAsValueRange<TypeAttr>(),
                                       [](Type field) { return isErased(field); });
  }

  int internJoin(Operation *op, unsigned number) {
    unsigned side = static_cast<unsigned>(joins.size());
    joins.push_back(armsOf(op));
    int found = -1;
    for (OpResult result : op->getResults()) {
      Node node;
      node.kind = Node::Join;
      node.arg = result.getResultNumber();
      node.side = side;
      int id = place(result, std::move(node));
      if (result.getResultNumber() == number)
        found = id;
    }
    return found;
  }

  SmallVector<Arm, 2> armsOf(Operation *op) {
    SmallVector<Arm, 2> arms;
    for (Region &region : op->getRegions()) {
      Arm arm;
      if (region.empty()) {
        arm.empty = true;
        arms.push_back(std::move(arm));
        continue;
      }
      Operation *end = region.front().getTerminator();
      if (isa<ub::UnreachableOp>(end)) {
        arm.unreachable = true;
      } else if (isa<YieldOp>(end)) {
        arm.yield = true;
        arm.frames = framesAt(end);
        for (Value operand : end->getOperands())
          arm.values.push_back(intern(operand));
      } else {
        arm.empty = true;
      }
      arms.push_back(std::move(arm));
    }
    return arms;
  }

  int internResult(OpResult result) {
    Operation *op = result.getOwner();
    if (isa<MatchOp, MatchLitOp>(op))
      return internJoin(op, result.getResultNumber());
    if (auto call = dyn_cast<func::CallOp>(op))
      return defineCall(call);
    Node node;
    if (isa<LinEnterOp, LinUseOp>(op)) {
      node.kind = Node::Copy;
      node.src = intern(op->getOperand(0));
    } else if (auto read = dyn_cast<FieldOp>(op)) {
      node.kind = Node::Field;
      node.src = intern(read.getValue());
      node.ctor = read.getCtorAttr().getAttr();
      node.arg = static_cast<unsigned>(read.getIndex());
      node.type = read.getType();
      node.memo = memoType(read.getValue().getType());
    } else if (auto pred = dyn_cast<BigPredOp>(op)) {
      node.kind = Node::Pred;
      node.src = intern(pred.getValue());
    } else if (auto con = dyn_cast<ConOp>(op)) {
      node.kind = Node::Con;
      node.ctor = con.getCtor().getLeafReference();
      node.type = con.getType();
      node.memo = memoType(con.getType());
      for (Value field : con.getFields()) {
        node.ops.push_back(intern(field));
        node.types.push_back(field.getType());
      }
    } else if (auto add = dyn_cast<BigAddOp>(op)) {
      node.kind = Node::Add;
      Value lhs = add.getLhs();
      Value rhs = add.getRhs();
      Value rest = isOne(rhs) ? lhs : isOne(lhs) ? rhs : Value();
      node.src = rest ? intern(rest) : -1;
    } else {
      Attribute constant;
      if (matchPattern(result, m_Constant(&constant)))
        encodeConst(node, result, constant);
    }
    return place(result, std::move(node));
  }

  SmallVector<Frame, 2> framesAt(Operation *at) {
    SmallVector<Frame, 2> frames;
    for (Region *region = at->getParentRegion(); region; region = region->getParentRegion()) {
      Operation *parent = region->getParentOp();
      if (parent == fn.getOperation())
        break;
      unsigned regionNumber = region->getRegionNumber();
      if (auto match = dyn_cast<MatchOp>(parent)) {
        Frame frame;
        frame.scrutinee = intern(match.getScrutinee());
        if (regionNumber < match.getCases().size()) {
          frame.named = true;
          frame.ctor = caseCtor(match, regionNumber);
        } else if (StringAttr rest = remaining(match)) {
          frame.named = true;
          frame.ctor = rest;
        }
        frames.push_back(frame);
      } else if (auto literal = dyn_cast<MatchLitOp>(parent)) {
        Frame frame;
        frame.lit = true;
        frame.scrutinee = intern(literal.getScrutinee());
        if (regionNumber < literal.getCases().size()) {
          frame.named = true;
          frame.literal = literal.getCases()[regionNumber];
        }
        frames.push_back(frame);
      }
    }
    return frames;
  }

  bool record(func::ReturnOp ret) {
    if (ret.getNumOperands() != 1)
      return false;
    rets.push_back({intern(ret.getOperand(0)), framesAt(ret.getOperation())});
    return true;
  }

  // The one descent. Match regions are part of what only computes; a call
  // that does not only allocate is kept to be justified from the record;
  // any other op must only allocate, and is not opened again.
  bool scan(Region &region) {
    for (Block &block : region) {
      if (llvm::any_of(block.getArgumentTypes(), owns))
        return false;
      for (BlockArgument arg : block.getArguments())
        intern(arg);
      for (Operation &op : block)
        if (!accept(op))
          return false;
    }
    return true;
  }

  bool accept(Operation &op) {
    if (llvm::any_of(op.getResultTypes(), owns))
      return false;
    if (op.hasTrait<OpTrait::IsTerminator>()) {
      if (!isa<func::ReturnOp, YieldOp, ub::UnreachableOp>(op))
        return false;
      if (auto ret = dyn_cast<func::ReturnOp>(op))
        return record(ret);
      return true;
    }
    if (isa<MatchOp, MatchLitOp>(op)) {
      for (Region &region : op.getRegions())
        if (!scan(region))
          return false;
      if (op.getNumResults())
        intern(op.getResult(0));
      return true;
    }
    if (auto call = dyn_cast<func::CallOp>(op)) {
      int id = defineCall(call);
      ::size_t node = static_cast<::size_t>(id);
      if (!nodes[node].allocates)
        reliant.push_back(id);
      return true;
    }
    if (!onlyAllocates(&op))
      return false;
    bool ok = true;
    if (op.getNumRegions())
      op.walk([&](func::ReturnOp ret) { ok = record(ret) && ok; });
    for (Value result : op.getResults())
      intern(result);
    return ok;
  }

  bool stable(const Assumed &assumed) const {
    if (!cached)
      return false;
    for (const Snapshot &snap : saved) {
      auto it = assumed.find(snap.name);
      bool present = it != assumed.end();
      if (present != snap.params.has_value())
        return false;
      if (present && *snap.params != it->second)
        return false;
    }
    return true;
  }

  void readCallee(StringAttr name) {
    if (!consulted.insert(name).second)
      return;
    auto it = live->find(name);
    if (it == live->end())
      saved.push_back({name, std::nullopt});
    else
      saved.push_back({name, it->second});
  }

  void fill(::size_t node) {
    if (memo[node].epoch == epoch)
      return;
    memo[node].epoch = epoch;
    unsigned slots = static_cast<unsigned>(arguments.size());
    memo[node].parts.assign(slots, std::nullopt);
    switch (nodes[node].kind) {
    case Node::Entry: {
      auto it = index.find(nodes[node].arg);
      if (it != index.end())
        memo[node].parts[it->second] = Parts::whole;
      break;
    }
    case Node::MatchArg: {
      if (nodes[node].memo)
        break;
      ::size_t src = static_cast<::size_t>(nodes[node].src);
      bool deflt = nodes[node].deflt;
      StringAttr ctor = nodes[node].ctor;
      unsigned arg = nodes[node].arg;
      Type type = nodes[node].type;
      fill(src);
      for (unsigned slot = 0; slot < slots; ++slot) {
        std::optional<unsigned> scr = memo[src].parts[slot];
        if (!scr)
          continue;
        memo[node].parts[slot] =
            deflt ? scr : std::optional<unsigned>(parts[slot].field(*scr, ctor, arg, type));
      }
      break;
    }
    case Node::Copy: {
      ::size_t src = static_cast<::size_t>(nodes[node].src);
      fill(src);
      memo[node].parts = memo[src].parts;
      break;
    }
    case Node::Field: {
      if (nodes[node].memo)
        break;
      ::size_t src = static_cast<::size_t>(nodes[node].src);
      StringAttr ctor = nodes[node].ctor;
      unsigned arg = nodes[node].arg;
      Type type = nodes[node].type;
      fill(src);
      for (unsigned slot = 0; slot < slots; ++slot) {
        std::optional<unsigned> of = memo[src].parts[slot];
        if (!of)
          continue;
        memo[node].parts[slot] = parts[slot].field(*of, ctor, arg, type);
      }
      break;
    }
    case Node::Pred: {
      ::size_t src = static_cast<::size_t>(nodes[node].src);
      fill(src);
      for (unsigned slot = 0; slot < slots; ++slot)
        if (std::optional<unsigned> of = memo[src].parts[slot])
          memo[node].parts[slot] = parts[slot].predecessor(*of);
      break;
    }
    case Node::Call: {
      StringAttr callee = nodes[node].callee;
      bool returns = nodes[node].returns;
      SmallVector<::size_t, 4> operands;
      for (int op : nodes[node].ops)
        operands.push_back(static_cast<::size_t>(op));
      readCallee(callee);
      auto found = live->find(callee);
      if (found == live->end())
        break;
      SmallVector<unsigned, 1> params = found->second;
      for (unsigned param : params)
        if (param < operands.size())
          fill(operands[param]);
      for (unsigned slot = 0; slot < slots; ++slot) {
        for (unsigned param : params) {
          if (param >= operands.size())
            continue;
          std::optional<unsigned> part = memo[operands[param]].parts[slot];
          if (part && (returns || parts[slot][*part].depth > 0)) {
            memo[node].parts[slot] = part;
            break;
          }
        }
      }
      break;
    }
    default:
      break;
    }
  }

  std::optional<unsigned> partOf(int node, unsigned slot) {
    if (node < 0)
      return std::nullopt;
    ::size_t id = static_cast<::size_t>(node);
    fill(id);
    return memo[id].parts[slot];
  }

  StringAttr singleCtor(Type type) {
    if (auto it = oneCtor.find(type); it != oneCtor.end())
      return it->second;
    StringAttr ctor;
    if (DataOp data = lookupData(fn, type)) {
      SmallVector<CtorOp> ctors = data.getCtors();
      if (ctors.size() == 1)
        ctor = ctors.front().getSymNameAttr();
    }
    oneCtor[type] = ctor;
    return ctor;
  }

  Known knownAt(unsigned part, ArrayRef<Frame> frames, unsigned slot) {
    for (const Frame &frame : frames) {
      std::optional<unsigned> scrutinee = partOf(frame.scrutinee, slot);
      if (!scrutinee || *scrutinee != part || !frame.named)
        continue;
      if (frame.lit)
        return {{}, frame.literal};
      return {frame.ctor, {}};
    }
    return {singleCtor(parts[slot][part].type), {}};
  }

  bool rebuilds(int node, unsigned part, ArrayRef<Frame> frames, unsigned slot) {
    if (std::optional<unsigned> is = partOf(node, slot); is && *is == part)
      return true;
    ::size_t id = static_cast<::size_t>(node);
    switch (nodes[id].kind) {
    case Node::Copy:
      return rebuilds(nodes[id].src, part, frames, slot);
    case Node::Con:
      return rebuildsCon(id, part, frames, slot);
    case Node::Add:
      return rebuildsSuccessor(id, part, frames, slot);
    case Node::Join:
      return rebuildsJoin(id, part, slot);
    case Node::Const:
      return rebuildsConstant(id, part, frames, slot);
    default:
      return false;
    }
  }

  bool rebuildsCon(::size_t node, unsigned part, ArrayRef<Frame> frames, unsigned slot) {
    StringAttr ctor = nodes[node].ctor;
    Type type = nodes[node].type;
    bool memoed = nodes[node].memo;
    SmallVector<int, 4> fields = nodes[node].ops;
    SmallVector<Type, 4> types = nodes[node].types;
    if (knownAt(part, frames, slot).ctor != ctor || unrestricted(type) != parts[slot][part].type ||
        memoed)
      return false;
    for (auto [at, field] : llvm::enumerate(fields)) {
      if (isErased(types[at]))
        continue;
      unsigned sub = parts[slot].field(part, ctor, static_cast<unsigned>(at), types[at]);
      if (!rebuilds(field, sub, frames, slot))
        return false;
    }
    return true;
  }

  // `S k` is n where k is n's predecessor: n is not zero, as the
  // predecessor op that k was read through shows by running at all.
  bool rebuildsSuccessor(::size_t node, unsigned part, ArrayRef<Frame> frames, unsigned slot) {
    if (!isa<NatType>(parts[slot][part].type))
      return false;
    if (nodes[node].src < 0)
      return false;
    return rebuilds(nodes[node].src, parts[slot].predecessor(part), frames, slot);
  }

  bool rebuildsJoin(::size_t node, unsigned part, unsigned slot) {
    unsigned side = nodes[node].side;
    unsigned result = nodes[node].arg;
    for (const Arm &arm : joins[side]) {
      if (arm.empty)
        return false;
      if (arm.unreachable)
        continue;
      if (!arm.yield || !rebuilds(arm.values[result], part, arm.frames, slot))
        return false;
    }
    return true;
  }

  bool rebuildsConstant(::size_t node, unsigned part, ArrayRef<Frame> frames, unsigned slot) {
    Known known = knownAt(part, frames, slot);
    if (known.literal)
      return nodes[node].attr == known.literal;
    if (!nodes[node].isCon || nodes[node].conRun || !known.ctor || nodes[node].ctor != known.ctor ||
        unrestricted(nodes[node].type) != parts[slot][part].type)
      return false;
    return nodes[node].erased;
  }

  void evaluate(const Assumed &assumed) {
    live = &assumed;
    saved.clear();
    consulted.clear();
    if (++epoch == 0) {
      for (Memo &item : memo)
        item.epoch = 0;
      epoch = 1;
    }
    answered.assign(arguments.size(), false);
    if (possible) {
      SmallVector<bool, 1> ok(arguments.size(), true);
      for (int id : reliant) {
        ::size_t call = static_cast<::size_t>(id);
        fill(call);
        for (unsigned slot = 0; slot < ok.size(); ++slot)
          if (ok[slot] && !memo[call].parts[slot])
            ok[slot] = false;
      }
      for (unsigned slot = 0; slot < ok.size(); ++slot) {
        if (!ok[slot])
          continue;
        bool all = true;
        for (const Ret &ret : rets)
          all = all && rebuilds(ret.value, Parts::whole, ret.frames, slot);
        answered[slot] = all;
      }
    }
    cached = true;
    live = nullptr;
  }

  func::FuncOp fn;
  bool possible = true;
  SmallVector<unsigned, 1> arguments;
  DenseMap<unsigned, unsigned> index;
  SmallVector<Parts, 1> parts;
  SmallVector<Node, 16> nodes;
  SmallVector<Memo, 16> memo;
  DenseMap<Value, int> ids;
  SmallVector<SmallVector<Arm, 2>, 1> joins;
  SmallVector<int, 2> reliant;
  SmallVector<Ret, 1> rets;
  DenseMap<Type, StringAttr> oneCtor;

  const Assumed *live = nullptr;
  bool cached = false;
  unsigned epoch = 0;
  SmallVector<bool, 1> answered;
  SmallVector<Snapshot, 2> saved;
  DenseSet<StringAttr> consulted;
};

Rebuilds::Rebuilds(func::FuncOp fn, ArrayRef<unsigned> candidates) : fn(fn) {
  for (unsigned argument : candidates) {
    index.try_emplace(argument, static_cast<unsigned>(arguments.size()));
    arguments.push_back(argument);
    parts.emplace_back(fn.getArgumentTypes()[argument]);
  }
  // Walk the body once. An owned value, a terminator this question cannot
  // keep, or an op that does not only allocate ends it: nothing is given
  // back, under any argument and any later assumptions, so the rest of the
  // body is not needed and is not walked again.
  if (arguments.empty() || !scan(fn.getBody())) {
    possible = false;
    nodes.clear();
    memo.clear();
    ids.clear();
    rets.clear();
    reliant.clear();
    joins.clear();
  }
}

SmallVector<unsigned, 1> Rebuilds::givesBack(ArrayRef<unsigned> asked, const Assumed &assumed) {
  if (!cached || !stable(assumed))
    evaluate(assumed);
  SmallVector<unsigned, 1> kept;
  for (unsigned argument : asked) {
    auto it = index.find(argument);
    if (it != index.end() && answered[it->second])
      kept.push_back(argument);
  }
  return kept;
}

} // namespace idr::identity
