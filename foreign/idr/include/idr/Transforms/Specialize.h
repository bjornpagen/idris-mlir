// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// Specialization: copies of a function keyed by what their callers know,
// each made once per key, by one clone-and-key template whatever the key
// says.
//
// A key is drawn from an alphabet. The optimizer's own keys are patterns
// of the arguments (a constructor, a closure's label with what it
// captures, a constant), compared by a well-quasi-order and lifted where
// two keys of one shape differ, so a recursion keeps finitely many copies.
// The other alphabets are finite: the layout class of a call's index
// arguments, the hold of a static argument where the callee would count,
// a lifetime's mode, a grade copy of counting's. Their keys are compared by
// equality and never lifted; their number is bounded by the alphabet. Every
// copy starts as a clone of its owner, so every parameter keeps the grade
// the owner gave it unless the key itself changes it.
//
// Keys are the run's own data: patterns and keys hash-consed in an arena
// freed with the run, never attributes of the context, so no worker takes
// a uniquer lock to judge a call and a refused request leaves nothing
// behind. A copy's name is a digest of its key's canonical bytes, the owner
// spelled by its symbol, so it is the same at any thread count and on any
// machine, and a name another key holds is the compiler's error.
#ifndef IDR_TRANSFORMS_SPECIALIZE_H
#define IDR_TRANSFORMS_SPECIALIZE_H

#include "idr/Analysis/BindingTimes.h"
#include "idr/Analysis/Solver/ProgramGraph.h"
#include "idr/IR/IdrDialect.h"
#include "idr/IR/Symbols.h"
#include "idr/Support/Actions.h"
#include "idr/Support/Match.h"

#include "mlir/IR/OwningOpRef.h"
#include "mlir/IR/PatternMatch.h"
#include "mlir/Pass/Pass.h"
#include "llvm/ADT/ArrayRef.h"
#include "llvm/ADT/DenseMap.h"
#include "llvm/ADT/Hashing.h"
#include "llvm/ADT/STLExtras.h"
#include "llvm/ADT/SmallVector.h"
#include "llvm/Support/Allocator.h"
#include "llvm/Support/raw_ostream.h"
#include "llvm/Support/xxhash.h"

#include <concepts>
#include <cstdint>
#include <memory>
#include <mutex>
#include <optional>
#include <span>
#include <variant>

namespace idr {

// idr-redirect calls a raise node: the call and its consumer become one
// call.
struct RaiseAction : support::TaggedAction<RaiseAction> {
  using TaggedAction::TaggedAction;
  static constexpr llvm::StringLiteral tag = "idr-raise";
};

// idr-redirect calls a copy of its callee.
struct SpecializeCloneAction : support::TaggedAction<SpecializeCloneAction> {
  using TaggedAction::TaggedAction;
  static constexpr llvm::StringLiteral tag = "idr-specialize-clone";
};

} // namespace idr

namespace idr::optimize {
class Schedule;
} // namespace idr::optimize

namespace idr::specialize {

using solver::FunctionId;

//===----------------------------------------------------------------------===//
// The canonical bytes a name is digested from
//===----------------------------------------------------------------------===//

// What a key writes of itself to be named: its owner by symbol, its tags
// and its constants' own bytes, never a printed form. One 128-bit digest
// of them is the copy's name, after its owner's symbol and its kind.
class Bytes {
public:
  void word(std::uint64_t value) {
    for (unsigned i = 0; i < 8; ++i)
      bytes.push_back(static_cast<std::uint8_t>(value >> (8 * i)));
  }
  void text(llvm::StringRef value) {
    word(value.size());
    bytes.append(value.bytes_begin(), value.bytes_end());
  }
  // A uniqued attribute's or type's content, by the digest of its content
  // computed once when it was made: the same in every process, where the
  // context's own hash of its storage is an address.
  void attribute(mlir::Attribute value) { digest128(stableDigest(value)); }
  void type(mlir::Type value) { digest128(stableDigest(value)); }
  void digest128(llvm::XXH128_hash_t value) {
    word(value.low64);
    word(value.high64);
  }
  llvm::XXH128_hash_t digest() const { return llvm::xxh3_128bits(bytes); }

private:
  llvm::SmallVector<std::uint8_t, 64> bytes;
};

//===----------------------------------------------------------------------===//
// Patterns: what a call knows of an argument where it is built
//===----------------------------------------------------------------------===//

class Pattern;

// A runtime value: the copy takes it as a parameter. The i-th hole of a
// key in pre-order is the copy's parameter i, and the call's i-th leaf.
struct Hole {
  friend bool operator==(Hole, Hole) = default;
};
// A constructor over the patterns of its fields: after defunctionalization
// a closure is a constructor of its family, its label the constructor and
// its captures the fields.
struct Con {
  Tag tag;
  llvm::ArrayRef<const Pattern *> fields;
};
// A constant the dialect builds again at the position's type: a scalar, a
// big, a string, a constant constructor (one constant, measured whole, so
// that a run never unrolls into a key).
struct Const {
  mlir::Attribute value;
};

// One of three, by type, hash-consed in the run's arena: equal patterns
// are one pointer, so a key is compared, hashed and embedded by its
// patterns' identities and their structure, never by text.
class Pattern {
public:
  using Node = std::variant<Hole, Con, Const>;
  explicit Pattern(Node node) : node(node) {}
  const Node &get() const { return node; }
  // A constructor, as a node or as a constant: a lone hole is none, and a
  // lone scalar is none either, since a number specialized on would make a
  // copy per value where LLVM weighs constant arguments better.
  bool hasStructure() const {
    return idr::match(
        node, [](Hole) { return false; }, [](const Con &) { return true; },
        [](const Const &constant) { return llvm::isa<ConAttr>(constant.value); });
  }
  unsigned holes() const { return holeCount; }

private:
  friend class Arena;
  Node node;
  unsigned holeCount = 0;
};

//===----------------------------------------------------------------------===//
// Keys
//===----------------------------------------------------------------------===//

// A specialization by patterns: the owner (the function the copy is cloned
// from) and a pattern per parameter of the owner.
struct PatternKey {
  FunctionId owner;
  llvm::ArrayRef<const Pattern *> params;
  unsigned holes() const;
};

// A consumer raised into its callee: the callee and the consumer's form,
// interned by its structure (Forms).
enum class FormId : std::uint32_t {};
struct RaiseKey {
  FunctionId callee;
  FormId form;
};

// A copy whose signature is the owner's with some types changed: an index
// argument's layout class fixed (a closed index term where the owner's
// layout changes under it), a parameter's hold made static where the
// caller passes static data, a lifetime parameter's kind fixed, a grade
// copy's grades. The target signature and the index terms substituted are
// the key; the alphabet is finite (the class set, the holds, the kinds,
// the grades are), so no order and no lift is needed.
struct SignatureKey {
  FunctionId owner;
  mlir::FunctionType signature;
  // The index arguments fixed in the copy, one per index binder of the
  // owner, `IndexArgsAttr::unknown()` where the binder stays.
  IndexArgsAttr indices;
};

// The arena of one run: every pattern and key it made, freed with it.
// Interning is under one lock: a request interns its key once, after it
// has judged it on its own requester's state.
class Arena {
public:
  const Pattern *hole();
  const Pattern *con(Tag tag, llvm::ArrayRef<const Pattern *> fields);
  const Pattern *constant(mlir::Attribute value);
  const PatternKey *key(FunctionId owner, llvm::ArrayRef<const Pattern *> params);
  const RaiseKey *key(FunctionId callee, FormId form);
  const SignatureKey *key(FunctionId owner, mlir::FunctionType signature,
                          IndexArgsAttr indices);

private:
  const Pattern *intern(Pattern::Node node, unsigned holes);
  llvm::ArrayRef<const Pattern *> copy(llvm::ArrayRef<const Pattern *> list);

  std::mutex mutex;
  llvm::BumpPtrAllocator storage;
  // Each pattern and key once, by its content: a constructor by its tag and
  // its fields' identities, a constant by its uniqued attribute.
  llvm::DenseMap<std::pair<unsigned, llvm::hash_code>, llvm::SmallVector<const void *, 1>> byHash;
};

// What a node is made from.
using Key = std::variant<const PatternKey *, const RaiseKey *, const SignatureKey *>;

//===----------------------------------------------------------------------===//
// The order keys of one owner are compared by, and lifting
//===----------------------------------------------------------------------===//

// Whether `key` grows `earlier`, two keys of one owner: `earlier` embeds in
// `key` (a homeomorphic embedding over their patterns, position by
// position) but not back. A key that grows an earlier one is the earlier
// key with more structure, which the table refuses. Embedding is a
// well-quasi-order on patterns of finitely many tags and kinds, so every
// sequence of keys none of which grows an earlier one is finite.
bool grows(const PatternKey &earlier, const PatternKey &key);

// Whether two keys of one owner are one shape: holes where holes are, one
// constructor where one is over fields of one shape, a scalar of one kind
// where one is, whatever its value.
bool sameShape(const PatternKey &a, const PatternKey &b);

// Where the operand of a hole of a lifted key comes from: the call's leaf
// of the hole it was, or a constant lifted out of the key, built at the
// call at its hole's type.
struct Kept {
  unsigned hole;
};
struct Lifted {
  mlir::Attribute constant;
};
using Source = std::variant<Kept, Lifted>;

// `key` with every scalar where it differs from any of `peers`, each a key
// of its shape, lifted out into a hole: anti-unification over the whole
// set at once, so the order in which the peers were met cannot reach the
// result. `sources` says, for each hole of the result in order, where its
// operand comes from. Each lift turns at least one scalar into a hole, so
// a request lifts finitely often.
const PatternKey *liftOver(Arena &arena, const PatternKey &key,
                           llvm::ArrayRef<const PatternKey *> peers,
                           llvm::SmallVectorImpl<Source> &sources);

//===----------------------------------------------------------------------===//
// The one clone-and-key template
//===----------------------------------------------------------------------===//

// How the keys of an alphabet are compared: by a well-quasi-order with a
// lift (the patterns), or by equality alone (a finite alphabet).
struct Embedding {};
struct Equality {};

// An alphabet of keys: how a key is named, which owner it is cloned from,
// how the clone is edited into the copy the key says, and how two keys
// are compared. The edit receives the owner's clone, so every parameter
// keeps the owner's grade unless the key changes it.
template <class A>
concept KeyAlphabet = requires(const typename A::Key &key, Bytes &bytes, FuncOp clone) {
  typename A::Key;
  typename A::Order;
  requires std::same_as<typename A::Order, Embedding> || std::same_as<typename A::Order, Equality>;
  { A::kind } -> std::convertible_to<llvm::StringRef>;
  { A::owner(key) } -> std::same_as<FunctionId>;
  { A::write(key, bytes) } -> std::same_as<void>;
  { A::edit(key, clone) } -> std::same_as<mlir::LogicalResult>;
};

// The name a key gives its copy: `<owner>.<kind>.<32 hex>`, from the
// digest of the key's canonical bytes. No Idris name holds the dots and a
// kind, so a copy's name is no function's of the program but an earlier
// copy of the same key.
template <KeyAlphabet A>
mlir::StringAttr nameOf(mlir::StringAttr owner, const typename A::Key &key) {
  Bytes bytes;
  bytes.text(owner.getValue());
  A::write(key, bytes);
  llvm::XXH128_hash_t digest = bytes.digest();
  llvm::SmallString<96> name(owner.getValue());
  llvm::raw_svector_ostream os(name);
  os << '.' << A::kind << '.';
  os << llvm::format_hex_no_prefix(digest.high64, 16) << llvm::format_hex_no_prefix(digest.low64, 16);
  return mlir::StringAttr::get(owner.getContext(), name);
}

// The copy of `owner` a key names: a detached clone, renamed, its row its
// owner's until the writer derives its own, edited as the key says. The
// one way a copy of a function is made, whatever alphabet keys it.
template <KeyAlphabet A>
mlir::FailureOr<FuncOp> makeCopy(FuncOp owner, const typename A::Key &key, mlir::StringAttr name) {
  auto clone = llvm::cast<FuncOp>(owner->clone());
  clone.setSymName(name.getValue());
  if (mlir::failed(A::edit(key, clone))) {
    clone->erase();
    return mlir::failure();
  }
  return clone;
}

// The optimizer's alphabets.
struct Patterns {
  using Key = const PatternKey *;
  using Order = Embedding;
  static constexpr llvm::StringLiteral kind = "spec";
  static FunctionId owner(Key key) { return key->owner; }
  static void write(Key key, Bytes &bytes);
  static mlir::LogicalResult edit(Key key, FuncOp clone);
};
struct Signatures {
  using Key = const SignatureKey *;
  using Order = Equality;
  static constexpr llvm::StringLiteral kind = "copy";
  static FunctionId owner(Key key) { return key->owner; }
  static void write(Key key, Bytes &bytes);
  static mlir::LogicalResult edit(Key key, FuncOp clone);
};
static_assert(KeyAlphabet<Patterns>);
static_assert(KeyAlphabet<Signatures>);

//===----------------------------------------------------------------------===//
// The nodes of one run
//===----------------------------------------------------------------------===//

// A node's phases, each holding what it has: asked for and not built;
// claimed by the one worker that builds it; built, detached, with its
// parameters' binding times; placed in the program as the function the
// schedule numbered.
struct Requested {};
struct Claimed {};
struct Built {
  FuncOp fn;
  llvm::SmallVector<BindingTime> times;
};
struct Placed {
  FunctionId id;
};
using Phase = std::variant<Requested, Claimed, Built, Placed>;

struct Node {
  Key key;
  // What inlining the copy does to the recursion its origin is on, the
  // function's own `copy` once the run ends: a step of a recursion on
  // static data, whose next step is another copy, so inlining it would
  // unroll the recursion into its callers; or a beta step, whose key fixes
  // closures alone, of labels outside the origin's component and none of
  // them shared, so inlined it consumes the constructors its caller built
  // and calls the recursion, never itself. None for a raise, a signature
  // copy, or a pattern copy of an origin on no cycle, which the inline
  // verdict weighs as any function. Decided when the key is granted; a
  // later request that shares a closure makes a beta step a step, and
  // nothing makes a step anything else.
  std::optional<CopyKind> copy;
  // The function the program held that it stands for, back through the
  // copies it was made from.
  FunctionId origin;
  mlir::FlatSymbolRefAttr name;
  // The nodes whose requests made it in the wave it was made, a set: the
  // keys on a request chain are read as a set, and its order is never.
  llvm::SmallVector<const Node *> parents;
  Phase phase = Requested{};
};

// The consumer forms raising has met: each a detached function, interned
// by upstream's structural equivalence (idr-deduplicate's) and known by
// the digest of its structure, which names the raise copies of it. The
// number a form gets is the order workers met it in, so nothing outside
// this table reads it: a name reads the digest. Safe from any worker; a
// form is never written once interned.
class Forms {
public:
  FormId intern(mlir::OwningOpRef<FuncOp> consumer);
  FuncOp at(FormId form) const;
  llvm::XXH128_hash_t digestOf(FormId form) const;

private:
  struct Form {
    mlir::OwningOpRef<FuncOp> fn;
    llvm::XXH128_hash_t digest;
  };
  mutable std::mutex mutex;
  llvm::DenseMap<std::uint64_t, llvm::SmallVector<FormId, 1>> byDigest;
  std::vector<Form> forms;
};

// What a requester asked for: the keys it was given, by owner, against
// which every key of that owner it asks for later is judged, and the nodes
// it has not taken yet. Held by the requester's turn, which one worker
// owns, so judging a request takes no lock.
class Requester {
public:
  llvm::ArrayRef<const PatternKey *> given(FunctionId owner) const;
  void give(Node &node);
  // The nodes given since the last take, in name order, each once.
  llvm::SmallVector<Node *> take();

private:
  llvm::SmallVector<std::pair<FunctionId, llvm::SmallVector<const PatternKey *, 2>>, 4> keys;
  llvm::SmallVector<Node *> waiting;
};

// What one call asks for.
struct PatternWant {
  const PatternKey *key;
  llvm::SmallVector<mlir::Value> leaves;
};
struct RaiseWant {
  const RaiseKey *key;
  Elimination consumer;
  llvm::SmallVector<mlir::Value> operands;
};
struct SignatureWant {
  const SignatureKey *key;
};
using Want = std::variant<PatternWant, RaiseWant, SignatureWant>;

// The table of one run: every node by key, the arena, the forms. Workers
// share it; a node is inserted and its phase moved under the lock, and
// nothing else is.
class Nodes {
public:
  explicit Nodes(const optimize::Schedule &schedule);
  ~Nodes();

  Arena &arena() { return keys; }
  Forms &forms() { return consumers; }

  // The node `fn` is, or null for a function the program held.
  const Node *find(FunctionId fn) const;

  // The node `want`'s key names for `requester`, judged on its own state
  // and made if new; none where the key grows one given before, or a lift
  // leaves no structure: the call stays a call. A name another key holds
  // is an internal error, emitted at `at`.
  struct Grant {
    Node *node;
    const PatternKey *key;
    llvm::SmallVector<Source> sources;
  };
  mlir::FailureOr<std::optional<Grant>> request(FunctionId requester, Requester &state,
                                                const Want &want, mlir::Operation *at);

  // True for exactly one caller per node: it goes from requested to
  // claimed.
  bool claim(Node &node);
  // The node's function, built detached from its owner as the schedule
  // lets `claimant` read it: it goes from claimed to built.
  mlir::LogicalResult build(Node &node, FunctionId claimant);
  // The node, built, was numbered by the schedule as `id`.
  void place(Node &node, FunctionId id);
  bool placed(const Node &node) const;
  // Once no turn runs: each placed copy's kind written on its function,
  // where the inline verdict reads it after the run.
  void writeCopies();

private:
  struct State;
  std::unique_ptr<State> state;
  Arena keys;
  Forms consumers;
};

// idr-redirect, a step of idr-optimize's inner pipeline: each call whose
// arguments compose a key, or whose result a dispatch consumes, requests
// its node and calls it.
std::unique_ptr<mlir::Pass> createRedirect(optimize::Schedule &schedule, Nodes &nodes,
                                           mlir::Pass::Statistic &redirected);

namespace detail {

// The pattern of `value` and its runtime leaves in pre-order, or a hole
// for a value no pattern knows more of. A constant is itself, a constructor
// its tag over its fields; a value entered into a quantity-one position is
// keyed as the value, whose position's type keeps its quantity.
const Pattern *shapeOf(Arena &arena, mlir::Value value, llvm::SmallVectorImpl<mlir::Value> &leaves);
// Whether `value` is closed (a constant, or a constructor of closed
// values), and whether every op that built its shape has one use.
bool isClosed(mlir::Value value);
bool usedOnce(mlir::Value value);
// Erases the ops that built the shapes of `values` once nothing uses them.
void eraseUnused(mlir::RewriterBase &rewriter, llvm::ArrayRef<mlir::Value> values);
// The value `pattern` stands for at a position of `type`, each hole taken
// from `holes[next++]`.
mlir::Value rebuild(mlir::OpBuilder &b, mlir::Location loc, const Pattern &pattern, mlir::Type type,
                    llvm::ArrayRef<mlir::Value> holes, unsigned &next);
void holeTypes(const Pattern &pattern, mlir::Type type, llvm::SmallVectorImpl<mlir::Type> &out);

// What a call fixes, by the binding times its callee's parameters have as
// the call sees them: a pattern key over the owner's parameters, or none.
// `own` is the callee's key when the callee is a pattern copy, its holes
// filled with the call's shapes.
std::optional<PatternWant> composeKey(Arena &arena, CallOp call, FunctionId owner,
                                      const PatternKey *own, llvm::ArrayRef<BindingTime> seen);

// What a pattern key fixes when it fixes closures alone: the labels of
// those closures, none of them capturing, at any depth, a closure of its
// own label; or data (a constructor of a data family, or a closure that
// would let a recursion walk), which a recursion could walk.
struct FixesData {};
struct FixesClosures {
  llvm::SmallVector<mlir::FlatSymbolRefAttr, 2> labels;
};
using Fixes = std::variant<FixesData, FixesClosures>;
Fixes fixes(const PatternKey &key, mlir::TypeRange params);

// Whether `call` passes a closure, or one a constructor it passes holds,
// that something else uses too.
bool sharesClosure(CallOp call);
// Where the call applies to a member of its own component closures built
// for it alone: fixed there, varying elsewhere.
std::optional<llvm::SmallVector<BindingTime>> appliesBuiltClosures(CallOp call);

// Raising.
std::optional<Elimination> consumerOf(CallOp call);
mlir::OwningOpRef<FuncOp> consumerFunction(CallOp call, const Elimination &consumer,
                                           llvm::SmallVectorImpl<mlir::Value> &free);
FuncOp buildRaise(FuncOp callee, const RaiseKey &key, mlir::StringAttr name, const Forms &forms);

// What a call wants, by kind: its signature copy where its index arguments
// fix a layout class the callee's layout changes under or it passes static
// data where the callee would count; else its raise; else its pattern key.
mlir::FailureOr<std::optional<Want>> decide(Arena &arena, Forms &forms, CallOp call,
                                            const Node *requester, FuncOp callee,
                                            FunctionId calleeId, const Node *calleeNode,
                                            llvm::ArrayRef<BindingTime> seen);

// Calling a node.
llvm::SmallVector<mlir::Value> operandsOf(mlir::RewriterBase &rewriter, CallOp call,
                                          const PatternWant &want, const PatternKey &key,
                                          llvm::ArrayRef<Source> sources, FuncOp owner);
CallOp redirect(mlir::RewriterBase &rewriter, CallOp call, mlir::FlatSymbolRefAttr target,
                mlir::FunctionType type, IndexArgsAttr indices,
                llvm::ArrayRef<mlir::Value> operands);
CallOp redirect(mlir::RewriterBase &rewriter, CallOp call, mlir::FlatSymbolRefAttr target,
                mlir::FunctionType type, const RaiseWant &want);

} // namespace detail
} // namespace idr::specialize

#endif // IDR_TRANSFORMS_SPECIALIZE_H
