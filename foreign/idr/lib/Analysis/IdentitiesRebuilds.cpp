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
#include "idr/Analysis/Identities.h"

#include "idr/IR/Grades.h"
#include "idr/IR/IdrDialect.h"
#include "idr/IR/Symbols.h"

#include "llvm/ADT/STLExtras.h"

using namespace mlir;

namespace idr {

bool Identities::Record::stable(const Assumed &assumed) const {
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

void Identities::Record::readCallee(StringAttr name) {
  if (!consulted.insert(name).second)
    return;
  auto it = live->find(name);
  if (it == live->end())
    saved.push_back({name, std::nullopt});
  else
    saved.push_back({name, it->second});
}

void Identities::Record::fill(std::size_t node) {
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
    auto src = static_cast<std::size_t>(nodes[node].src);
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
    auto src = static_cast<std::size_t>(nodes[node].src);
    fill(src);
    memo[node].parts = memo[src].parts;
    break;
  }
  case Node::Field: {
    if (nodes[node].memo)
      break;
    auto src = static_cast<std::size_t>(nodes[node].src);
    StringAttr ctor = nodes[node].ctor;
    unsigned arg = nodes[node].arg;
    Type type = nodes[node].type;
    fill(src);
    for (unsigned slot = 0; slot < slots; ++slot)
      if (std::optional<unsigned> of = memo[src].parts[slot])
        memo[node].parts[slot] = parts[slot].field(*of, ctor, arg, type);
    break;
  }
  case Node::Pred: {
    auto src = static_cast<std::size_t>(nodes[node].src);
    fill(src);
    for (unsigned slot = 0; slot < slots; ++slot)
      if (std::optional<unsigned> of = memo[src].parts[slot])
        memo[node].parts[slot] = parts[slot].predecessor(*of);
    break;
  }
  case Node::Call: {
    // The nodes and the assumptions stay as they are while the record is
    // read; only the memo and the parts grow.
    const Node &call = nodes[node];
    readCallee(call.callee);
    auto found = live->find(call.callee);
    if (found == live->end())
      break;
    ArrayRef<unsigned> params = found->second;
    auto operand = [&](unsigned param) { return static_cast<std::size_t>(call.ops[param]); };
    for (unsigned param : params)
      if (param < call.ops.size())
        fill(operand(param));
    for (unsigned slot = 0; slot < slots; ++slot) {
      for (unsigned param : params) {
        if (param >= call.ops.size())
          continue;
        std::optional<unsigned> part = memo[operand(param)].parts[slot];
        if (part && (call.returns || parts[slot][*part].depth > 0)) {
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

std::optional<unsigned> Identities::Record::partOf(int node, unsigned slot) {
  if (node < 0)
    return std::nullopt;
  auto id = static_cast<std::size_t>(node);
  fill(id);
  return memo[id].parts[slot];
}

StringAttr Identities::Record::singleCtor(Type type) {
  if (auto it = oneCtor.find(type); it != oneCtor.end())
    return it->second;
  StringAttr ctor;
  if (DataOp data = lookupData(symbols, type)) {
    SmallVector<CtorOp> ctors = data.getCtors();
    if (ctors.size() == 1)
      ctor = ctors.front().getSymNameAttr();
  }
  oneCtor[type] = ctor;
  return ctor;
}

Identities::Record::Known Identities::Record::knownAt(unsigned part, ArrayRef<Frame> frames,
                                                      unsigned slot) {
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

bool Identities::Record::rebuilds(int node, unsigned part, ArrayRef<Frame> frames, unsigned slot) {
  if (std::optional<unsigned> is = partOf(node, slot); is && *is == part)
    return true;
  auto id = static_cast<std::size_t>(node);
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

bool Identities::Record::rebuildsCon(std::size_t node, unsigned part, ArrayRef<Frame> frames,
                                     unsigned slot) {
  const Node &con = nodes[node];
  if (con.memo || knownAt(part, frames, slot).ctor != con.ctor ||
      unrestricted(con.type) != parts[slot][part].type)
    return false;
  for (auto [at, field] : llvm::enumerate(con.ops)) {
    unsigned sub = parts[slot].field(part, con.ctor, static_cast<unsigned>(at), con.types[at]);
    if (!rebuilds(field, sub, frames, slot))
      return false;
  }
  return true;
}

// `S k` is n where k is n's predecessor: n is not zero, as the predecessor
// op that k was read through shows by running at all.
bool Identities::Record::rebuildsSuccessor(std::size_t node, unsigned part, ArrayRef<Frame> frames,
                                           unsigned slot) {
  if (!isa<NatType>(parts[slot][part].type) || nodes[node].src < 0)
    return false;
  return rebuilds(nodes[node].src, parts[slot].predecessor(part), frames, slot);
}

bool Identities::Record::rebuildsJoin(std::size_t node, unsigned part, unsigned slot) {
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

bool Identities::Record::rebuildsConstant(std::size_t node, unsigned part, ArrayRef<Frame> frames,
                                          unsigned slot) {
  Known known = knownAt(part, frames, slot);
  if (known.literal)
    return nodes[node].attr == known.literal;
  if (!nodes[node].isCon || nodes[node].conRun || !known.ctor || nodes[node].ctor != known.ctor ||
      unrestricted(nodes[node].type) != parts[slot][part].type)
    return false;
  return nodes[node].fieldless;
}

void Identities::Record::evaluate(const Assumed &assumed) {
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
      auto call = static_cast<std::size_t>(id);
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

SmallVector<unsigned, 1> Identities::Record::givesBack(ArrayRef<unsigned> asked,
                                                        const Assumed &assumed) {
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

} // namespace idr
