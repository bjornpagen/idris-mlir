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
// The other keys are compared by equality and never lifted, and are
// finitely many by construction. The layout class of a call's index
// arguments, the hold of a static argument where the callee would count,
// the layout each result is returned at, a lifetime's mode and a grade copy
// of counting's are each drawn from a finite alphabet. A result is returned
// as its class lays it out (closed: `#Vect[4]` in place, every non-tail
// call's) or, for a tail call whose caller lays it out otherwise, at the
// open layout, its type marked open, its indices kept: a copy keyed open
// returns that, so the two lower to one return. A copy keyed open asks only
// open: each of its tails gives the open layout, so each tail call in it
// whose callee gives a closed result asks that callee open in turn, at the
// grade the copy returns it at. A result's open form is its type marked
// open at that grade, the mark one of two, so the axis at most doubles the
// keys of each class and hold, and the copies end with no budget and no
// fixpoint. A result no copy could give closed, since a tail of its owner
// gives it at what no substitution closes, is no key's: the owner's own
// type marks it open (openResults), every copy returns it open by the
// substitution, which keeps the mark, and its class lays it out open.
//
// A size an axis becomes is not drawn from a finite alphabet: the naturals
// are unbounded. A size keys a copy only from a call outside its callee's call
// cycle, or from one inside it whose terms for that axis are terms its
// caller's body holds as its own; a recursive call that changes the term
// (`go (S n)` called at 0) reaches the copy with that axis `?`. So every
// size the copies of a cycle are keyed at entered it by one of the
// finitely many calls into it, and specialization on sizes ends with no
// budget and no number; an axis is static besides only where a layout
// class fixes its index variable, which the class alphabet bounds. Every
// copy starts as a clone of its owner, so every parameter keeps the grade
// the owner gave it unless the key itself changes it.
//
// Keys are the run's own data: patterns and keys hash-consed in an arena
// freed with the run, never attributes of the context, so no worker takes
// a uniquer lock to judge a call and a refused request leaves nothing
// behind. A copy's name is a digest of its key's canonical bytes, the owner
// spelled by its symbol, so it is the same at any thread count and on any
// machine, and a name another key holds is the compiler's error.
//
// The nodes of one run, which these keys make, are SpecializeState.h's.
#ifndef IDR_TRANSFORMS_SPECIALIZE_H
#define IDR_TRANSFORMS_SPECIALIZE_H

#include "idr/Analysis/BindingTimes.h"
#include "idr/Analysis/Solver/ProgramGraph.h"
#include "idr/IR/Generated/Actions.h.inc"
#include "idr/IR/IdrDialect.h"
#include "idr/IR/Symbols.h"
#include "idr/Support/Actions.h"
#include "idr/Support/Footprint.h"
#include "idr/Support/Match.h"

#include "mlir/IR/OwningOpRef.h"
#include "mlir/IR/PatternMatch.h"
#include "mlir/Pass/Pass.h"
#include "llvm/ADT/ArrayRef.h"
#include "llvm/ADT/Hashing.h"
#include "llvm/ADT/STLExtras.h"
#include "llvm/ADT/SmallVector.h"
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
  static constexpr std::string_view tag = ::idr::actions::raise;
};

// idr-redirect calls a copy of its callee.
struct SpecializeCloneAction : support::TaggedAction<SpecializeCloneAction> {
  using TaggedAction::TaggedAction;
  static constexpr std::string_view tag = ::idr::actions::specializeClone;
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
// layout changes under it), a bare tensor argument's axis made static
// where the index term naming it becomes a constant, a parameter's hold
// made static where the caller passes static data, a result at the open
// layout where a tail call's caller returns it so, a lifetime parameter's
// kind fixed, a grade copy's grades. The target signature and the index
// terms substituted are the key, so a result's layout is read off its type
// there, as a hold is. The classes, holds, layouts, kinds and grades are
// finite alphabets, and the sizes are those that entered each call cycle
// from outside it, so no order and no lift is needed.
struct SignatureKey {
  FunctionId owner;
  mlir::FunctionType signature;
  // The index arguments fixed in the copy, one per index binder of the
  // owner: a closed term where the class fixes the binder, and where the
  // binder stays the level it becomes in the copy, the k-th kept level k.
  IndexArgsAttr indices;
};

// The type a copy keyed open returns `type` at, for a caller that holds the
// value as `held`: a data type marked open, laid out as at an unknown index
// with the indices Idris proved and its refinement kept, at the grade
// `held` has, so a cast to a type of that grade laid out so builds nothing
// and keeps the hold; any other type as it is, whose layout no index
// decides.
mlir::Type openResult(mlir::Type type, mlir::Type held);

// `fn` returning `results`, which differ from its own results only where
// one opens: every tail of it gives that result at the open type, what it
// gave there cast to it once, and each call in it takes the tail fact its
// place now gives it.
void openTails(FuncOp fn, llvm::ArrayRef<mlir::Type> results);

// The one rule for a result a tail of its function gives at a layout the
// function's own type cannot agree with, in the function or in a copy whose
// classes would close it: the function's result is marked open in its own
// type, at the hold that tail gives, its tails give it open, and every call
// of it takes the open type and casts it back after itself. Decided once for
// each function the program held when the schedule takes it up, between
// waves, for `starters`, each a member a turn of the coming wave starts: its
// callers outside its component wait on it, and a caller of its component
// that loses a tail to the cast is decided again in turn. Every copy keeps
// the mark its owner's type gives it.
void openResults(optimize::Schedule &schedule, llvm::ArrayRef<FunctionId> starters);

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
  footprint::BumpPtrAllocator storage;
  // Each pattern and key once, by its content: a constructor by its tag and
  // its fields' identities, a constant by its uniqued attribute.
  footprint::DenseMap<std::pair<unsigned, llvm::hash_code>, llvm::SmallVector<const void *, 1>> byHash;
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
// lift (the patterns), or by equality alone (keys finitely many by how
// they are asked).
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

} // namespace idr::specialize

#endif // IDR_TRANSFORMS_SPECIALIZE_H
