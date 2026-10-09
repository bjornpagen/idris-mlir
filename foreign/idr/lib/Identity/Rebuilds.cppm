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

// The check of one function and one of its parameters, the argument.
class Rebuilds {
public:
  Rebuilds(func::FuncOp fn, unsigned argument, const Assumed &assumed)
      : fn(fn), argument(argument), assumed(assumed), parts(fn.getArgumentTypes()[argument]) {}

  // Whether `fn` only computes and every return gives back the argument.
  bool givesBack() {
    if (!onlyComputes(fn.getBody()))
      return false;
    bool all = true;
    fn.walk([&](func::ReturnOp ret) {
      all = all && ret.getNumOperands() == 1 && rebuilds(ret.getOperand(0), Parts::whole, ret);
    });
    return all;
  }

private:
  // What a part is known to be where a value stands for it: built by a
  // constructor, a literal, or neither.
  struct Known {
    StringAttr ctor;
    Attribute literal;
  };

  // A value that holds or borrows a reference: the owned stage's.
  static bool owns(Type type) { return gradeOf(type).permission != Permission::None; }

  // A constant big one.
  static bool isOne(Value value) {
    Attribute constant;
    auto big = matchPattern(value, m_Constant(&constant)) ? dyn_cast<BigAttr>(constant) : BigAttr();
    return big && big.getValue() == "1";
  }

  // A memo sum's cell holds the state of a suspension, which suspensions
  // may close into a cycle, so nothing in it is below it.
  bool memo(Type type) {
    DataOp data = lookupData(fn, type);
    return data && isMemo(data);
  }

  static StringAttr caseCtor(MatchOp match, unsigned region) {
    return cast<FlatSymbolRefAttr>(match.getCases()[region]).getAttr();
  }

  bool onlyComputes(Region &region) {
    for (Block &block : region) {
      if (llvm::any_of(block.getArgumentTypes(), owns))
        return false;
      for (Operation &op : block)
        if (!onlyComputes(op))
          return false;
    }
    return true;
  }

  bool onlyComputes(Operation &op) {
    if (llvm::any_of(op.getResultTypes(), owns))
      return false;
    if (op.hasTrait<OpTrait::IsTerminator>())
      return isa<func::ReturnOp, YieldOp, ub::UnreachableOp>(op);
    if (isa<MatchOp, MatchLitOp>(op))
      return llvm::all_of(op.getRegions(), [&](Region &region) { return onlyComputes(region); });
    if (auto call = dyn_cast<func::CallOp>(op); call && assumedParam(call))
      return true;
    return onlyAllocates(&op);
  }

  // The parameter of `call`'s callee assumed given back that the call may
  // rely on, if any: one to which it passes a part strictly below the
  // argument, or any part when the callee's facts say it returns.
  std::optional<unsigned> assumedParam(func::CallOp call) {
    StringAttr callee = call.getCalleeAttr().getAttr();
    auto it = assumed.find(callee);
    if (it == assumed.end())
      return std::nullopt;
    bool returns = !facts::of(lookupSymbol<func::FuncOp>(fn, callee)).diverge;
    for (unsigned param : it->second) {
      if (param >= call.getNumOperands())
        continue;
      std::optional<unsigned> part = partOf(call.getOperand(param));
      if (part && (returns || parts[*part].depth > 0))
        return param;
    }
    return std::nullopt;
  }

  // The part of the argument `value` is, if it is one.
  std::optional<unsigned> partOf(Value value) {
    if (auto it = seen.find(value); it != seen.end())
      return it->second;
    std::optional<unsigned> part = findPart(value);
    seen[value] = part;
    return part;
  }

  std::optional<unsigned> findPart(Value value) {
    if (auto arg = dyn_cast<BlockArgument>(value)) {
      Block *block = arg.getOwner();
      if (block == &fn.getBody().front()) {
        if (arg.getArgNumber() != argument)
          return std::nullopt;
        return Parts::whole;
      }
      auto match = dyn_cast_or_null<MatchOp>(block->getParentOp());
      if (!match || memo(match.getScrutinee().getType()))
        return std::nullopt;
      std::optional<unsigned> scrutinee = partOf(match.getScrutinee());
      unsigned region = block->getParent()->getRegionNumber();
      // The default region takes the scrutinee back.
      if (!scrutinee || region >= match.getCases().size())
        return scrutinee;
      return parts.field(*scrutinee, caseCtor(match, region), arg.getArgNumber(), arg.getType());
    }
    Operation *op = value.getDefiningOp();
    if (isa<LinEnterOp, LinUseOp>(op))
      return partOf(op->getOperand(0));
    if (auto read = dyn_cast<FieldOp>(op)) {
      std::optional<unsigned> of = partOf(read.getValue());
      if (!of || memo(read.getValue().getType()))
        return std::nullopt;
      return parts.field(*of, read.getCtorAttr().getAttr(), static_cast<unsigned>(read.getIndex()),
                         read.getType());
    }
    if (auto pred = dyn_cast<BigPredOp>(op)) {
      std::optional<unsigned> of = partOf(pred.getValue());
      if (!of)
        return std::nullopt;
      return parts.predecessor(*of);
    }
    if (auto call = dyn_cast<func::CallOp>(op))
      if (std::optional<unsigned> param = assumedParam(call))
        return partOf(call.getOperand(*param));
    return std::nullopt;
  }

  // What `part` is known to be at `at`.
  Known knownAt(unsigned part, Operation *at) {
    for (Region *region = at->getParentRegion(); region; region = region->getParentRegion()) {
      Operation *parent = region->getParentOp();
      if (parent == fn.getOperation())
        break;
      unsigned index = region->getRegionNumber();
      if (auto match = dyn_cast<MatchOp>(parent)) {
        std::optional<unsigned> scrutinee = partOf(match.getScrutinee());
        if (!scrutinee || *scrutinee != part)
          continue;
        if (index < match.getCases().size())
          return {caseCtor(match, index), {}};
        if (StringAttr rest = remaining(match))
          return {rest, {}};
      } else if (auto literal = dyn_cast<MatchLitOp>(parent)) {
        std::optional<unsigned> scrutinee = partOf(literal.getScrutinee());
        if (scrutinee && *scrutinee == part && index < literal.getCases().size())
          return {{}, literal.getCases()[index]};
      }
    }
    if (DataOp data = lookupData(fn, parts[part].type)) {
      SmallVector<CtorOp> ctors = data.getCtors();
      if (ctors.size() == 1)
        return {ctors.front().getSymNameAttr(), {}};
    }
    return {};
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

  // Whether `value` is the part `part` rebuilt where `use` reads it.
  bool rebuilds(Value value, unsigned part, Operation *use) {
    if (std::optional<unsigned> is = partOf(value); is && *is == part)
      return true;
    Operation *op = value.getDefiningOp();
    if (!op)
      return false;
    if (isa<LinEnterOp, LinUseOp>(op))
      return rebuilds(op->getOperand(0), part, use);
    if (auto con = dyn_cast<ConOp>(op))
      return rebuildsCon(con, part, use);
    if (auto add = dyn_cast<BigAddOp>(op))
      return rebuildsSuccessor(add, part, use);
    if (isa<MatchOp, MatchLitOp>(op))
      return rebuildsJoin(op, cast<OpResult>(value).getResultNumber(), part);
    Attribute constant;
    if (matchPattern(value, m_Constant(&constant)))
      return rebuildsConstant(constant, value.getType(), part, use);
    return false;
  }

  bool rebuildsCon(ConOp con, unsigned part, Operation *use) {
    StringAttr ctor = con.getCtor().getLeafReference();
    if (knownAt(part, use).ctor != ctor || unrestricted(con.getType()) != parts[part].type ||
        memo(con.getType()))
      return false;
    for (auto [index, field] : llvm::enumerate(con.getFields())) {
      if (isErased(field.getType()))
        continue;
      unsigned sub = parts.field(part, ctor, static_cast<unsigned>(index), field.getType());
      if (!rebuilds(field, sub, use))
        return false;
    }
    return true;
  }

  // `S k` is n where k is n's predecessor: n is not zero, as the
  // predecessor op that k was read through shows by running at all.
  bool rebuildsSuccessor(BigAddOp add, unsigned part, Operation *use) {
    if (!isa<NatType>(parts[part].type))
      return false;
    Value lhs = add.getLhs();
    Value rhs = add.getRhs();
    Value rest = isOne(rhs) ? lhs : isOne(lhs) ? rhs : Value();
    return rest && rebuilds(rest, parts.predecessor(part), use);
  }

  bool rebuildsJoin(Operation *match, unsigned result, unsigned part) {
    for (Region &region : match->getRegions()) {
      if (region.empty())
        return false;
      Operation *end = region.front().getTerminator();
      if (isa<ub::UnreachableOp>(end))
        continue;
      if (!isa<YieldOp>(end) || !rebuilds(end->getOperand(result), part, end))
        return false;
    }
    return true;
  }

  bool rebuildsConstant(Attribute constant, Type type, unsigned part, Operation *use) {
    Known known = knownAt(part, use);
    if (known.literal)
      return constant == known.literal;
    auto con = dyn_cast<ConAttr>(constant);
    if (!known.ctor || !con || con.isRun() || con.getCtor().getLeafReference() != known.ctor ||
        unrestricted(type) != parts[part].type)
      return false;
    CtorOp ctor = lookupCtor(fn, con.getCtor());
    return ctor && llvm::all_of(ctor.getFieldTypes().getAsValueRange<TypeAttr>(),
                                [](Type field) { return isErased(field); });
  }

  func::FuncOp fn;
  unsigned argument;
  const Assumed &assumed;
  Parts parts;
  DenseMap<Value, std::optional<unsigned>> seen;
};

} // namespace idr::identity
