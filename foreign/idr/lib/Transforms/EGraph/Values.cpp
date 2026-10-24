// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The e-graph's own values and the one fold's value instance over them.
//
// A constant the graph knows is a value of its own until the write-back
// places it: an integer, the one value of its class's interval; a Double,
// by its bits; and a string or a big past the small range as the runtime
// holds it, one reference of the graph's own. A big in the small range the
// runtime holds in its word, so it is an integer, as the runtime's
// representation says. An op whose meaning is a runtime function computes
// over these through the one fold (IR/Fold.h), the same row, call and
// reading of integers as the op's MLIR fold, which is its attribute
// instance; so a constant is computed once, by the runtime's own function,
// and no attribute is made until the write-back places one, here too.
//
// A guard is decided by its own condition (its op's `decide`) over the
// graph's values: each operand's interval, an integer the one value of its
// class's, and the string, Double or big past the small range its class
// holds, whether an op held it or the graph computed it. The same decision
// is asked where an op the guard guards computes, and, by the guard's class
// of op, where the skeleton rule decides the guard (the table `decisions`
// gives). A big past the small range has the interval its sign gives too.
// An op whose fold has a condition beyond its guards states it over
// attributes (its `foldable` hook), so the graph does not compute it.
//
// Upstream's ops on Doubles whose result IEEE 754 fixes (the generated
// ComputedOnDoubles) compute on the graph's Double values by the operation
// each op's own fold applies, APFloat's at round-to-nearest-even or, for a
// root, the host's correctly rounded `sqrt`, so the op means what upstream
// documents and no second meaning is written; a NaN result is no constant,
// as the one fold's refusal says.

#include "idr/Transforms/EGraph/Engine.h"

#include "idr/IR/Fold.h"
#include "idr/IR/Ranges.h"

#include "mlir/Dialect/Arith/IR/Arith.h"
#include "mlir/Dialect/Math/IR/Math.h"
#include "mlir/IR/BuiltinAttributes.h"
#include "llvm/ADT/APFloat.h"
#include "llvm/Support/ErrorHandling.h"

#include <bit>
#include <cmath>
#include <cstdint>
#include <vector>

// The generated list of upstream's ops on Doubles the graph computes.
#include "idr/IR/Generated/Rewrites.h.inc"

using namespace mlir;

namespace idr::egraph {

//===----------------------------------------------------------------------===//
// The values
//===----------------------------------------------------------------------===//

// A string's bytes never change; its count, in its header, is the one word
// a reference writes.
Text Text::share(const idris_rt_str *s) {
  idris_rt_inc_cell(&const_cast<idris_rt_str *>(s)->header);
  return Text(s);
}

Text::~Text() {
  if (s)
    idris_rt_dec_cell(&const_cast<idris_rt_str *>(s)->header);
}

Big Big::share(idris_rt_big b) {
  idris_rt_inc_big(b);
  return Big(b);
}

Big::~Big() { idris_rt_dec_big(word); }

bool operator==(const Big &a, const Big &b) {
  return runtime::Abi<BigCmpOp>::function(a.word, b.word) == 0;
}

// A held constant is its attribute; a built one its constructor's data
// type, and its parts, each with its type. Its hash is
// computed once, when it is made, of its parts' own. A built constant may
// hold a chain of built constants as deep as the program's text makes it,
// so every walk over one keeps its place on a stack of its own, and a node
// releases the nodes it alone holds one after another, never one inside
// another's destructor.
struct Data::Node {
  ConAttr held;
  DataType data;
  llvm::SmallVector<Part, 2> parts;
  std::size_t hash = 0;

  ~Node();
};

namespace {

// The built constant a part is, the one walk down a built constant takes;
// null for any other part.
const Data *builtIn(const Part &part) {
  const auto *constant = std::get_if<Constant>(&part.value);
  const Data *data = constant ? std::get_if<Data>(constant) : nullptr;
  return data && !data->heldValue() ? data : nullptr;
}

std::size_t hashOfParts(llvm::hash_code head, llvm::ArrayRef<Part> parts) {
  llvm::hash_code hash = head;
  for (const Part &part : parts)
    hash = llvm::hash_combine(
        hash, part.type.getAsOpaquePointer(),
        match(
            part.value, [](const APInt &integer) { return llvm::hash_value(integer); },
            [](const Constant &constant) { return detail::hash_value(constant); }));
  return static_cast<std::size_t>(hash);
}

} // namespace

Data::Node::~Node() {
  footprint::Vector<std::shared_ptr<const Node>> pending;
  auto unlink = [&](llvm::SmallVector<Part, 2> &from) {
    for (Part &part : from)
      if (auto *constant = std::get_if<Constant>(&part.value))
        if (auto *data = std::get_if<Data>(constant); data && data->node.use_count() == 1)
          pending.push_back(std::move(data->node));
  };
  unlink(parts);
  while (!pending.empty()) {
    std::shared_ptr<const Node> last = std::move(pending.back());
    pending.pop_back();
    // `last` is the one owner of its node, which goes at the end of this
    // turn with no node of its own left to release.
    unlink(const_cast<Node &>(*last).parts);
  }
}

Data Data::held(ConAttr value) {
  auto node = std::make_shared<Node>();
  node->held = value;
  node->hash = static_cast<std::size_t>(llvm::hash_value(value.getAsOpaquePointer()));
  return Data(std::move(node));
}

Data Data::constructor(DataType data, llvm::SmallVector<Part, 2> fields) {
  auto node = std::make_shared<Node>();
  node->data = data;
  node->hash = hashOfParts(llvm::hash_value(data.getAsOpaquePointer()), fields);
  node->parts = std::move(fields);
  return Data(std::move(node));
}

ConAttr Data::heldValue() const { return node->held; }
DataType Data::builtData() const { return node->data; }
llvm::ArrayRef<Part> Data::parts() const { return node->parts; }
std::size_t Data::hash() const { return node->hash; }

// A held constructor's tag is its attribute's; a built one's, its data
// type's one constructor, to which an idr.data.con's result is refined.
Tag Data::tag() const {
  if (node->held)
    return node->held.getTag();
  return *node->data.singleTag();
}

// Pair by pair down both, each pair of built parts compared after the pair
// that holds them.
bool operator==(const Data &a, const Data &b) {
  footprint::Vector<std::pair<const Data::Node *, const Data::Node *>> work{
      {a.node.get(), b.node.get()}};
  while (!work.empty()) {
    auto [x, y] = work.back();
    work.pop_back();
    if (x == y)
      continue;
    if (x->hash != y->hash)
      return false;
    if (x->held || y->held) {
      if (x->held != y->held)
        return false;
      continue;
    }
    if (x->data != y->data || x->parts.size() != y->parts.size())
      return false;
    for (auto [p, q] : llvm::zip_equal(x->parts, y->parts)) {
      if (p.type != q.type || p.value.index() != q.value.index())
        return false;
      if (const auto *integer = std::get_if<APInt>(&p.value)) {
        const APInt &other = std::get<APInt>(q.value);
        if (integer->getBitWidth() != other.getBitWidth() || *integer != other)
          return false;
        continue;
      }
      const Data *inner = builtIn(p), *otherInner = builtIn(q);
      if (inner && otherInner) {
        work.push_back({inner->node.get(), otherInner->node.get()});
        continue;
      }
      if (!(std::get<Constant>(p.value) == std::get<Constant>(q.value)))
        return false;
    }
  }
  return true;
}

} // namespace idr::egraph

namespace idr::egraph::detail {

// A big's word past the small range is its cell's address.
namespace {
const idris_rt_bignum *cellOf(const Big &big) {
  return reinterpret_cast<const idris_rt_bignum *>(static_cast<std::uintptr_t>(big.get()));
}
} // namespace

// Equal values hash alike: a big by its value modulo 2^64, the runtime's
// own conversion to a word.
llvm::hash_code hash_value(const Constant &constant) {
  return match(
      constant, [](const Text &text) { return llvm::hash_value(text.bytes()); },
      [](const Real &real) { return llvm::hash_value(real.bits); },
      [](const Big &big) {
        return llvm::hash_value(runtime::Abi<BigToIntOp>::function(big.get()));
      },
      [](const Data &data) { return llvm::hash_code(data.hash()); });
}

std::uint64_t bytesOf(const Constant &constant) {
  return match(
      constant,
      [](const Text &text) -> std::uint64_t { return sizeof(idris_rt_str) + text.get()->bytes; },
      [](const Real &) -> std::uint64_t { return 0; },
      [](const Big &big) -> std::uint64_t {
        std::int64_t limbs = cellOf(big)->size;
        return sizeof(idris_rt_bignum) +
               static_cast<std::uint64_t>(limbs < 0 ? -limbs : limbs) * IDRIS_RT_WORD_BYTES;
      },
      // A held one is static data already; a built one holds its parts,
      // shared with the constants they are.
      [](const Data &data) -> std::uint64_t { return data.parts().size() * sizeof(Part); });
}

// A string and a big past the small range are static data, in a cell; a
// held constructor stands where idr.constant holds its attribute, and a
// built one where it would hold the attribute made of it.
bool placedAt(const Constant &constant, Type type) {
  return match(
      constant, [&](const Real &) { return type.isF64(); },
      [&](const OneOf<Text, Big> auto &) {
        return fold::constantStandsAt(type, fold::Storage::Cell);
      },
      [&](const Data &data) {
        if (ConAttr held = data.heldValue())
          return ConstantOp::isBuildableWith(held, type);
        return fold::constructorStandsAt(data.builtData(), type);
      });
}

// Static data stands where a hold that claims nothing is asked, whoever
// frees it (Hold::fits, the grade order), so a use that took a value of
// `type` by that order takes the static data too; the type it stands at is
// one where idr.constant stands, fold::constantStandsAt says. A value used
// once has no static form: static data is used any number of times.
std::optional<Type> staticFormOf(const Constant &constant, Type type) {
  return match(
      constant,
      [](const OneOf<Real, Data> auto &) -> std::optional<Type> { return std::nullopt; },
      [&](const OneOf<Text, Big> auto &) -> std::optional<Type> {
        std::optional<Hold> hold = holdOf(type);
        if (!hold || !Hold::staticData().fits(*hold))
          return std::nullopt;
        Type held = atHold(type, Hold::staticData());
        if (!fold::constantStandsAt(held, fold::Storage::Cell))
          return std::nullopt;
        return held;
      });
}

namespace {

// A big as the graph knows it: in the small range, the one value of its
// interval, as the runtime holds it in its word; past it, its cell, and the
// interval its sign gives, which the runtime's comparison with 0 reads: a
// bound at the small range's end on that side and none beyond, as the
// ranges of bigs read an interval, so the value is known not to be 0.
Facts factsOfBig(Big big) {
  idris_rt_big word = big.get();
  if (idris_rt_word_is_small(word)) {
    std::int64_t value = idris_rt_small_value(word);
    return {ranges::rangeOf(ranges::bounded(value, value)), std::nullopt};
  }
  idris_rt_big zero = runtime::Abi<BigSmallOp>::function(0);
  ranges::Bounds past = runtime::Abi<BigCmpOp>::function(word, zero) > 0
                            ? ranges::bounded(IDRIS_RT_SMALL_MAX, std::nullopt)
                            : ranges::bounded(std::nullopt, IDRIS_RT_SMALL_MIN);
  return {ranges::rangeOf(past), std::move(big)};
}

// The interval a guard reads of an operand: its class's, or every value of
// its type, of no width where it holds no integer.
ConstantIntRanges guardRange(const Class &cls) {
  if (cls.facts.range)
    return *cls.facts.range;
  unsigned width = ConstantIntRanges::getStorageBitwidth(cls.type);
  if (width == 0)
    return ConstantIntRanges::constant(APInt::getZero(0));
  return ConstantIntRanges::maxRange(width);
}

// Each operand's interval, as a guard reads it.
SmallVector<ConstantIntRanges, 4> intervalsOf(llvm::ArrayRef<const Class *> operands) {
  SmallVector<ConstantIntRanges, 4> out;
  out.reserve(operands.size());
  for (const Class *cls : operands)
    out.push_back(guardRange(*cls));
  return out;
}

//===----------------------------------------------------------------------===//
// The value instance
//===----------------------------------------------------------------------===//

// The constructor constant a class holds, borrowed from it.
const Data *dataOf(const Class *cls) {
  return cls->facts.constant ? std::get_if<Data>(&*cls->facts.constant) : nullptr;
}

// What a part of a built constant says of its value.
Facts factsOfPart(const Part &part) {
  return match(
      part.value,
      [](const APInt &integer) {
        return Facts{ConstantIntRanges::constant(integer), std::nullopt};
      },
      [](const Constant &constant) { return factsOf(constant); });
}

// The parts a constructor is built of: each class's constant, an integer
// or another, with the class's type; none where one is no constant.
std::optional<llvm::SmallVector<Part, 2>> partsOf(llvm::ArrayRef<const Class *> classes) {
  llvm::SmallVector<Part, 2> parts;
  for (const Class *cls : classes) {
    if (std::optional<APInt> integer = cls->facts.integer())
      parts.push_back(Part{*integer, cls->type});
    else if (cls->facts.constant)
      parts.push_back(Part{*cls->facts.constant, cls->type});
    else
      return std::nullopt;
  }
  return parts;
}

// A constructor constant's first cell: a held attribute's run's, or a
// built one.
std::variant<fold::RunCell, const Data *> cellOfData(const Data &data) {
  if (ConAttr con = data.heldValue())
    return fold::RunCell{con, 0};
  return &data;
}

// Part `index` of a built constant, none past its parts.
const Part *partOf(const Data &built, unsigned index) {
  return index < built.parts().size() ? &built.parts()[index] : nullptr;
}

// The one fold where a constant is what a class's facts say: read from an
// operand's root class, and made as the facts the computing node says.
// Nothing it reads is copied, and what the runtime makes is the graph's.
class InGraph {
public:
  using Operand = const Class *;
  using Result = Facts;
  // A value is a class of the function's graph, which a composite fold
  // reads where it asks how an operand was built.
  using Given = ClassId;

  InGraph() = default;
  explicit InGraph(const Function &function) : function(&function) {}

  ClassId given(Value, const Class *cls) const { return function->idOf(*cls); }

  template <class OpT>
  std::optional<fold::Built<InGraph, OpT>> builtBy(Value, const Class *cls) const {
    auto built = function->builtOf<OpT>(*cls);
    if (!built)
      return std::nullopt;
    return fold::Built<InGraph, OpT>{built->first, std::move(built->second)};
  }

  std::optional<APInt> integerOf(const Class *cls) const { return cls->facts.integer(); }

  std::optional<double> realOf(const Class *cls) const {
    if (!cls->facts.constant)
      return std::nullopt;
    return match(
        *cls->facts.constant,
        [](const Real &real) -> std::optional<double> { return real.value(); },
        [](const OneOf<Text, Big, Data> auto &) -> std::optional<double> { return std::nullopt; });
  }

  std::optional<const idris_rt_str *> strOf(const Class *cls) const {
    if (!cls->facts.constant)
      return std::nullopt;
    return match(
        *cls->facts.constant,
        [](const Text &text) -> std::optional<const idris_rt_str *> { return text.get(); },
        [](const OneOf<Real, Big, Data> auto &) -> std::optional<const idris_rt_str *> {
          return std::nullopt;
        });
  }

  // A big in the small range is its interval's one value, which the
  // runtime's word for it holds, with no cell to keep.
  std::optional<idris_rt_big> bigOf(const Class *cls) const {
    if (cls->facts.constant)
      return match(
          *cls->facts.constant,
          [](const Big &big) -> std::optional<idris_rt_big> { return big.get(); },
          [](const OneOf<Text, Real, Data> auto &) -> std::optional<idris_rt_big> {
            return std::nullopt;
          });
    if (!cls->facts.range)
      return std::nullopt;
    ranges::Bounds bounds = ranges::boundsOf(*cls->facts.range);
    if (!bounds.lo || !bounds.hi || *bounds.lo != *bounds.hi)
      return std::nullopt;
    return runtime::Abi<BigSmallOp>::function(*bounds.lo);
  }

  std::optional<Facts> integer(Type, const APInt &value) const {
    return Facts{ConstantIntRanges::constant(value), std::nullopt};
  }
  std::optional<Facts> real(Type, double value) const {
    return Facts{std::nullopt, Real{std::bit_cast<std::uint64_t>(value)}};
  }
  std::optional<Facts> str(Type, const idris_rt_str *made) const {
    return Facts{std::nullopt, Text::adopt(made)};
  }
  std::optional<Facts> big(Type, idris_rt_big made) const { return factsOfBig(Big::adopt(made)); }

  // The composite folds' place (FoldParts.h). A constructor constant is
  // read a cell at a time: a held attribute's cells where its run holds
  // them, a built one's parts, so a walk down either makes no attribute. A
  // field a cell holds is a constant of the graph: a held attribute's field
  // read as an op holding it is, a built one's part; the spine of a held
  // run's cell is the next cell, which no attribute holds until one is
  // made, which the graph never makes, so that field stays a read.
  using Cell = std::variant<fold::RunCell, const Data *>;

  std::optional<Cell> cellOf(const Class *cls) const {
    const Data *data = dataOf(cls);
    return data ? std::optional<Cell>(cellOfData(*data)) : std::nullopt;
  }

  Tag tagAt(const Cell &cell) const {
    return match(
        cell, [](const fold::RunCell &held) { return held.tag(); },
        [](const Data *built) { return built->tag(); });
  }

  std::uint64_t afterAt(const Cell &cell) const {
    return match(
        cell, [](const fold::RunCell &held) { return held.after(); },
        [](const Data *) -> std::uint64_t { return 0; });
  }

  Cell lastAt(const Cell &cell) const {
    return match(
        cell, [](const fold::RunCell &held) -> Cell { return held.last(); },
        [](const Data *built) -> Cell { return built; });
  }

  std::optional<Cell> nextAt(const Cell &cell, unsigned index) const {
    return match(
        cell,
        [&](const fold::RunCell &held) -> std::optional<Cell> {
          if (std::optional<fold::RunCell> next = held.next(index))
            return Cell(*next);
          return std::nullopt;
        },
        [&](const Data *built) -> std::optional<Cell> {
          const Part *part = partOf(*built, index);
          const auto *constant = part ? std::get_if<Constant>(&part->value) : nullptr;
          const Data *data = constant ? std::get_if<Data>(constant) : nullptr;
          return data ? std::optional<Cell>(cellOfData(*data)) : std::nullopt;
        });
  }

  std::optional<APInt> integerAt(const Cell &cell, unsigned index) const {
    return match(
        cell, [&](const fold::RunCell &held) { return fold::integerOf(held.field(index)); },
        [&](const Data *built) -> std::optional<APInt> {
          const Part *part = partOf(*built, index);
          const auto *integer = part ? std::get_if<APInt>(&part->value) : nullptr;
          return integer ? std::optional(*integer) : std::nullopt;
        });
  }

  // A held attribute's string is made for the read, kept by `scope`; a
  // built part's is the graph's own, borrowed.
  std::optional<const idris_rt_str *> strAt(fold::Scope &scope, const Cell &cell,
                                            unsigned index) const {
    return match(
        cell, [&](const fold::RunCell &held) { return fold::strOf(scope, held.field(index)); },
        [&](const Data *built) -> std::optional<const idris_rt_str *> {
          const Part *part = partOf(*built, index);
          const auto *constant = part ? std::get_if<Constant>(&part->value) : nullptr;
          const Text *text = constant ? std::get_if<Text>(constant) : nullptr;
          return text ? std::optional(text->get()) : std::nullopt;
        });
  }

  std::optional<Facts> fieldOf(const Class *cls, unsigned index, Type) const {
    const Data *data = dataOf(cls);
    if (!data)
      return std::nullopt;
    return match(
        cellOfData(*data),
        [&](const fold::RunCell &held) -> std::optional<Facts> {
          mlir::Attribute field = held.field(index);
          return field ? std::optional<Facts>(heldFacts(field)) : std::nullopt;
        },
        [&](const Data *built) -> std::optional<Facts> {
          const Part *part = partOf(*built, index);
          return part ? std::optional<Facts>(factsOfPart(*part)) : std::nullopt;
        });
  }

  // The leaf rule of a constant's parts over the graph's values: a word of
  // exactly its field's type; a big or a natural in the small range, which
  // stands in its word wherever it is used any number of times; or a
  // constant idr.constant holds at it. An attribute's literal check (a
  // natural is never negative, and is its closed index) refuses a literal
  // written by hand; a value the graph knows of a class of the type is a
  // value of that type, which its type proves, so it is the type's literal
  // and nothing tests it again.
  bool buildable(const Class *cls, Type type) const {
    if (cls->type != type)
      return false;
    if (std::optional<APInt> value = cls->facts.integer()) {
      std::optional<IntegerForm> form = integerFormOf(type);
      if (form == IntegerForm::Small)
        return fold::constantStandsAt(type, fold::Storage::Word);
      return form == IntegerForm::Word && isFieldType(type) &&
             value->getBitWidth() == ConstantIntRanges::getStorageBitwidth(type);
    }
    return cls->facts.constant && placedAt(*cls->facts.constant, type);
  }

  std::optional<Facts> constructor(Type, const DataType &data,
                                   llvm::ArrayRef<const Class *> fields) const {
    std::optional<llvm::SmallVector<Part, 2>> parts = partsOf(fields);
    if (!parts)
      return std::nullopt;
    return Facts{std::nullopt, Data::constructor(data, std::move(*parts))};
  }

  // The same value under another type: the constant past an interval a class
  // holds, a string or a big past the small range, which no width ties to
  // its type; an integer the op's own interval says at its own type.
  std::optional<Facts> same(Type, const Class *cls) const {
    if (!cls->facts.constant)
      return std::nullopt;
    return Facts{std::nullopt, *cls->facts.constant};
  }

  // The function whose graph a composite fold reads; none where only
  // constants are read.
  const Function *function = nullptr;

  // The op computes only where each of its guards holds of the graph's
  // values (each guard's own decision, read off its op).
  template <class Op>
  bool admits(llvm::ArrayRef<const Class *> operands) {
    if constexpr (fold::HasFoldCondition<Op>)
      return false;
    else if constexpr (fold::GuardedFold<Op, InGraph>)
      return Op::guardsHold(*this, intervalsOf(operands), operands);
    else
      return true;
  }
};

static_assert(fold::Where<InGraph>, "the graph's values are a place a constant lives");
static_assert(fold::Composite<InGraph>,
              "the graph's values hold constructors of constants");

template <class Op>
std::optional<Facts> meaningOf(llvm::ArrayRef<const Class *> operands, Type type,
                               const typename Op::Properties &properties) {
  InGraph where;
  return fold::evaluate<Op>(where, operands, type, properties);
}

template <class Op>
std::optional<Facts> ofInput(const Function &, Operation *op, Type type,
                             llvm::ArrayRef<const Class *> operands) {
  return meaningOf<Op>(operands, type, cast<Op>(op).getProperties());
}

template <class Op>
std::optional<Facts> ofBuilt(Type type, llvm::ArrayRef<const Class *> operands) {
  return meaningOf<Op>(operands, type, typename Op::Properties{});
}

// An op of ours whose fold is one of constants made of constants, its
// condition its `meaning` over a place (Ops/Folds.h), which gives a
// constant; or one whose fold may give a value instead (fold::Folded). No
// rule builds one, so it has no meaning of a built node.
template <class Op>
concept Composes = requires(InGraph &where, Op op, llvm::ArrayRef<const Class *> constants) {
  { Op::meaning(where, op, constants) } -> std::same_as<std::optional<Facts>>;
};
template <class Op>
concept Gives = requires(InGraph &where, Op op, llvm::ArrayRef<const Class *> constants) {
  { Op::meaning(where, op, constants) } -> std::same_as<std::optional<fold::Folded<InGraph>>>;
};

template <class Op>
std::optional<Facts> composed(const Function &function, Operation *op, Type,
                              llvm::ArrayRef<const Class *> operands) {
  InGraph where(function);
  if constexpr (Gives<Op>) {
    std::optional<fold::Folded<InGraph>> folded = Op::meaning(where, cast<Op>(op), operands);
    if (Facts *constant = folded ? std::get_if<Facts>(&*folded) : nullptr)
      return std::move(*constant);
    return std::nullopt;
  } else {
    return Op::meaning(where, cast<Op>(op), operands);
  }
}

template <class Op>
std::optional<ClassId> givenBy(const Function &function, Operation *op,
                               llvm::ArrayRef<const Class *> operands) {
  InGraph where(function);
  std::optional<fold::Folded<InGraph>> folded = Op::meaning(where, cast<Op>(op), operands);
  if (const ClassId *value = folded ? std::get_if<ClassId>(&*folded) : nullptr)
    return *value;
  return std::nullopt;
}

// Each op of ours whose meaning is its runtime function, by its trait, or
// a composite fold, by its `meaning`.
template <class... Ops>
void runtimeMeaningsOf(std::vector<std::pair<TypeID, Meaning>> &out) {
  (
      [&] {
        if constexpr (fold::Folds<Ops>)
          out.emplace_back(TypeID::get<Ops>(), Meaning{&ofInput<Ops>, &ofBuilt<Ops>, std::nullopt});
        else if constexpr (Composes<Ops>)
          out.emplace_back(TypeID::get<Ops>(),
                           Meaning{&composed<Ops>, std::nullopt, std::nullopt});
        else if constexpr (Gives<Ops>)
          out.emplace_back(TypeID::get<Ops>(),
                           Meaning{&composed<Ops>, std::nullopt, &givenBy<Ops>});
      }(),
      ...);
}

// A guard's own decision of its operands' classes, its condition over the
// graph's values.
template <class Op>
numeric::Known decisionOf(llvm::ArrayRef<const Class *> operands) {
  InGraph where;
  return Op::decide(where, intervalsOf(operands), operands);
}

// Each guard op's decision, by its interface's trait.
template <class... Ops>
void decisionsOf(std::vector<std::pair<TypeID, Decision>> &out) {
  (
      [&] {
        if constexpr (Ops::template hasTrait<GuardOpInterface::Trait>())
          out.emplace_back(TypeID::get<Ops>(), &decisionOf<Ops>);
      }(),
      ...);
}

//===----------------------------------------------------------------------===//
// Upstream's ops on Doubles
//===----------------------------------------------------------------------===//

// A Double a class holds, as the IEEE double its bits are; none where it
// holds no Double.
std::optional<APFloat> doubleOf(const Class *cls) {
  if (!cls->facts.constant)
    return std::nullopt;
  return match(
      *cls->facts.constant,
      [](const Real &real) -> std::optional<APFloat> {
        return APFloat(APFloat::IEEEdouble(), APInt(64, real.bits));
      },
      [](const OneOf<Text, Big, Data> auto &) -> std::optional<APFloat> { return std::nullopt; });
}

// The Double an operation gave, as the graph's: none where IEEE leaves it
// to each machine (fold::ieeeOn, a NaN's sign and payload).
std::optional<Facts> computed(const APFloat &value) {
  if (fold::ieeeOn(value) == fold::Ieee::LeavesOpen)
    return std::nullopt;
  return Facts{std::nullopt, Real{value.bitcastToAPInt().getZExtValue()}};
}

// Whether an op rounds as Idris's Double does, to nearest with ties to
// even: the rounding its fold applies where it names none, the default
// floating-point environment. An op that names another computes what the
// graph does not: it stays applied.
template <class Op>
bool nearestEven(Op op) {
  std::optional<arith::RoundingMode> mode = op.getRoundingmode();
  return !mode || *mode == arith::RoundingMode::to_nearest_even;
}

// Each op's computation, the operation its own upstream fold applies to two
// constant operands, named once for the op it is; the ops are the
// generated list's, and an op on it with no computation here does not
// compile.
template <class Op>
struct OnDoubles;

// arith.addf, subf, mulf and divf: APFloat's add, subtract, multiply and
// divide of the first by the second, as each one's fold computes
// `APFloat result(a); result.op(b, rounding)`, at round-to-nearest-even,
// the rounding it applies where the op names none.
template <APFloat::opStatus (APFloat::*Apply)(const APFloat &, APFloat::roundingMode)>
struct Rounded {
  template <class Op>
  static std::optional<Facts> of(Op op, llvm::ArrayRef<const Class *> operands, Type) {
    std::optional<APFloat> a = doubleOf(operands[0]), b = doubleOf(operands[1]);
    if (!a || !b || !nearestEven(op))
      return std::nullopt;
    APFloat result(*a);
    (void)(result.*Apply)(*b, APFloat::rmNearestTiesToEven);
    return computed(result);
  }
};

template <>
struct OnDoubles<arith::AddFOp> : Rounded<&APFloat::add> {};
template <>
struct OnDoubles<arith::SubFOp> : Rounded<&APFloat::subtract> {};
template <>
struct OnDoubles<arith::MulFOp> : Rounded<&APFloat::multiply> {};
template <>
struct OnDoubles<arith::DivFOp> : Rounded<&APFloat::divide> {};

// arith.negf: its operand with its sign changed, its fold's `-a`.
template <>
struct OnDoubles<arith::NegFOp> {
  static std::optional<Facts> of(arith::NegFOp, llvm::ArrayRef<const Class *> operands, Type) {
    std::optional<APFloat> a = doubleOf(operands[0]);
    return a ? computed(-*a) : std::nullopt;
  }
};

// math.floor and math.ceil: the operand rounded to an integral value
// toward negative and positive infinity, as each one's fold computes it by
// APFloat's roundToIntegral.
template <APFloat::roundingMode Toward>
struct Integral {
  template <class Op>
  static std::optional<Facts> of(Op, llvm::ArrayRef<const Class *> operands, Type) {
    std::optional<APFloat> a = doubleOf(operands[0]);
    if (!a)
      return std::nullopt;
    APFloat result(*a);
    (void)result.roundToIntegral(Toward);
    return computed(result);
  }
};

template <>
struct OnDoubles<math::FloorOp> : Integral<APFloat::rmTowardNegative> {};
template <>
struct OnDoubles<math::CeilOp> : Integral<APFloat::rmTowardPositive> {};

// math.sqrt: the host's square root of the operand's double, as its fold
// computes it, which IEEE 754 requires correctly rounded, so every machine
// computes what the target does. Of a number below zero it is a NaN, which
// is no constant (computed), and of -0 it is -0.
template <>
struct OnDoubles<math::SqrtOp> {
  static std::optional<Facts> of(math::SqrtOp, llvm::ArrayRef<const Class *> operands, Type) {
    std::optional<APFloat> a = doubleOf(operands[0]);
    if (!a)
      return std::nullopt;
    return computed(APFloat(std::sqrt(a->convertToDouble())));
  }
};

// arith.sitofp and uitofp: the integer as each reads it, with its sign or
// without, converted at round-to-nearest-even, as each one's fold computes
// it by APFloat's convertFromAPInt in its result's semantics. A Double is
// the graph's one float, so a result of another width is none of its
// values.
template <numeric::Signedness Reading>
struct FromInteger {
  template <class Op>
  static std::optional<Facts> of(Op, llvm::ArrayRef<const Class *> operands, Type type) {
    std::optional<APInt> integer = operands[0]->facts.integer();
    if (!integer || !type.isF64())
      return std::nullopt;
    APFloat result(APFloat::IEEEdouble(), APInt::getZero(64));
    (void)result.convertFromAPInt(*integer, Reading == numeric::Signedness::Signed,
                                  APFloat::rmNearestTiesToEven);
    return computed(result);
  }
};

template <>
struct OnDoubles<arith::SIToFPOp> : FromInteger<numeric::Signedness::Signed> {};
template <>
struct OnDoubles<arith::UIToFPOp> : FromInteger<numeric::Signedness::Unsigned> {};

// arith.cmpf: the op's predicate on the two, by upstream's own
// applyCmpPredicate, which its fold calls; a truth, an i1.
template <>
struct OnDoubles<arith::CmpFOp> {
  static std::optional<Facts> of(arith::CmpFOp op, llvm::ArrayRef<const Class *> operands, Type) {
    std::optional<APFloat> a = doubleOf(operands[0]), b = doubleOf(operands[1]);
    if (!a || !b)
      return std::nullopt;
    bool holds = arith::applyCmpPredicate(op.getPredicate(), *a, *b);
    return Facts{ConstantIntRanges::constant(APInt(1, holds)), std::nullopt};
  }
};

template <class Op>
std::optional<Facts> onDoubles(const Function &, Operation *op, Type type,
                               llvm::ArrayRef<const Class *> operands) {
  return OnDoubles<Op>::of(cast<Op>(op), operands, type);
}

// Each op of the generated list: no rule builds one, so it has no meaning
// of a built node.
template <class... Ops>
void doubleMeaningsOf(table::OpList<Ops...>, std::vector<std::pair<TypeID, Meaning>> &out) {
  (out.emplace_back(TypeID::get<Ops>(), Meaning{&onDoubles<Ops>, std::nullopt, std::nullopt}),
   ...);
}

//===----------------------------------------------------------------------===//
// What a runtime function borrows
//===----------------------------------------------------------------------===//

// An op the lowering calls its runtime function for, by its generated row.
template <class Op>
concept HasRuntimeRow = requires { runtime::Abi<Op>::operands; };

// The positions at which `Op`'s function takes a string or a big. Every
// primitive borrows its arguments, as the runtime's ABI states, so a
// reference it takes is held by whatever holds it at the call. The row has
// one kind per operand, and the positions of every row fit.
template <class Op>
consteval Borrowed borrowedBy() {
  using Row = runtime::Abi<Op>;
  static_assert(std::size(Row::operands) <= Borrowed::most, "a row's operands fit its positions");
  Borrowed out;
  for (unsigned at = 0; at < std::size(Row::operands); ++at)
    if (Row::operands[at] == runtime::OperandKind::Str ||
        Row::operands[at] == runtime::OperandKind::Big)
      out = out.with(at);
  return out;
}

template <class... Ops>
void borrowingsOf(std::vector<std::pair<TypeID, Borrowed>> &out) {
  (
      [&] {
        if constexpr (HasRuntimeRow<Ops>) {
          constexpr Borrowed borrowed = borrowedBy<Ops>();
          if constexpr (!borrowed.empty())
            out.emplace_back(TypeID::get<Ops>(), borrowed);
        }
      }(),
      ...);
}

} // namespace

// A dialect materializes what it folds to (MLIR's folding contract), and the
// graph makes a constant only where its op stands, so a constant class
// always has its op.
Value materialized(Dialect &dialect, RewriterBase &rewriter, Location loc, Type type,
                   Attribute value) {
  Operation *op = dialect.materializeConstant(rewriter, value, type, loc);
  if (!op)
    llvm::reportFatalInternalError("idr-simplify: a constant its dialect does not materialize "
                                   "at its type");
  return op->getResult(0);
}

std::vector<std::pair<TypeID, Meaning>> meanings() {
  std::vector<std::pair<TypeID, Meaning>> out;
  runtimeMeaningsOf<
#define GET_OP_LIST
#include "idr/IR/IdrOps.cpp.inc"
      >(out);
  doubleMeaningsOf(generated::ComputedOnDoubles{}, out);
  return out;
}

std::vector<std::pair<TypeID, Decision>> decisions() {
  std::vector<std::pair<TypeID, Decision>> out;
  decisionsOf<
#define GET_OP_LIST
#include "idr/IR/IdrOps.cpp.inc"
      >(out);
  return out;
}

std::vector<std::pair<TypeID, Borrowed>> borrowings() {
  std::vector<std::pair<TypeID, Borrowed>> out;
  borrowingsOf<
#define GET_OP_LIST
#include "idr/IR/IdrOps.cpp.inc"
      >(out);
  return out;
}

// A constant an op holds is read as what it says a fold reads of it, and
// kept as the graph's: a string or a big made by the attribute instance's
// readers, a reference of the graph's own beside the scope's, which the
// scope releases; a constructor held as it is. Any other
// attribute is no constant.
Facts heldFacts(Attribute value) {
  auto constant = dyn_cast<ConstantAttrInterface>(value);
  if (!constant)
    return {};
  return match(
      constant.getFoldValue(),
      [](const fold_value::Integer &integer) -> Facts {
        return {ConstantIntRanges::constant(integer.value), std::nullopt};
      },
      [](fold_value::Real real) -> Facts {
        return {std::nullopt, Real{std::bit_cast<std::uint64_t>(real.value)}};
      },
      [&](fold_value::Text text) -> Facts {
        fold::Scope scope(value.getContext());
        return {std::nullopt, Text::share(*fold::strOf(scope, text.value))};
      },
      [&](fold_value::Big big) -> Facts {
        fold::Scope scope(value.getContext());
        return factsOfBig(Big::share(*fold::bigOf(scope, big.value.get())));
      },
      [](const fold_value::Constructor &con) -> Facts {
        return {std::nullopt, Data::held(con.value.get())};
      },
      [](fold_value::Unread) -> Facts { return {}; });
}

Facts factsOf(const Constant &constant) {
  return match(
      constant, [](const Big &big) { return factsOfBig(big); },
      [](const OneOf<Text, Real, Data> auto &value) { return Facts{std::nullopt, value}; });
}

//===----------------------------------------------------------------------===//
// The write-back
//===----------------------------------------------------------------------===//

// A word and a splat are arith's constants; a small big is idr.constant's,
// which stands at any hold.
Value writeBack(RewriterBase &rewriter, Location loc, Type type, const node::Integer &integer,
                Dialect &constants) {
  TypedAttr value;
  switch (integer.form) {
  case IntegerForm::Word:
    value = IntegerAttr::get(type, integer.value);
    break;
  case IntegerForm::Splat:
    value = DenseIntElementsAttr::get(cast<ShapedType>(type), integer.value);
    break;
  case IntegerForm::Small:
    return materialized(constants, rewriter, loc, type,
                        BigAttr::get(rewriter.getContext(), integer.value));
  }
  return arith::ConstantOp::create(rewriter, loc, type, value).getResult();
}

// A Double is arith's constant of its bits; a string's and a big's
// attributes are the ones the runtime's results make in the one fold, at
// the type they are placed at: their class's, or the static form a use
// takes them at.
namespace {

// A part's attribute at its type, but for a built constant's, which its
// walk makes: an integer as a word of its type or a small big, a Double of
// its type, a string's bytes, a big's integer, or a held constant's own.
mlir::Attribute attributeOf(MLIRContext *context, const Part &part) {
  return match(
      part.value,
      [&](const APInt &integer) -> mlir::Attribute {
        if (integerFormOf(part.type) == IntegerForm::Small)
          return BigAttr::get(context, integer);
        return IntegerAttr::get(part.type, integer);
      },
      [&](const Constant &constant) {
        return match(
            constant,
            [&](const Real &real) -> mlir::Attribute {
              APFloat bits(APFloat::IEEEdouble(), APInt(64, real.bits));
              return FloatAttr::get(part.type, bits);
            },
            [&](const Text &text) { return fold::strAttr(context, text.get()); },
            [&](const Big &big) { return fold::bigAttr(context, big.get()); },
            [&](const Data &data) -> mlir::Attribute { return data.heldValue(); });
      });
}

// The attribute a constructor constant is, made here, at the write-back: a
// held one's own; a built one's of its parts' attributes, each built part
// made before the constant that holds it, on a stack of the constants still
// being made with the attributes of their parts so far.
mlir::Attribute attributeOf(MLIRContext *context, const Data &root) {
  if (ConAttr held = root.heldValue())
    return held;
  struct Making {
    const Data *data;
    llvm::SmallVector<mlir::Attribute> parts;
  };
  footprint::Vector<Making> stack;
  stack.push_back({&root, {}});
  mlir::Attribute made;
  while (!stack.empty()) {
    const Data *data = stack.back().data;
    std::size_t next = stack.back().parts.size();
    if (next < data->parts().size()) {
      const Part &part = data->parts()[next];
      if (const Data *inner = builtIn(part))
        stack.push_back({inner, {}});
      else
        stack.back().parts.push_back(attributeOf(context, part));
      continue;
    }
    made = ConAttr::get(context, data->builtData(), ArrayAttr::get(context, stack.back().parts));
    stack.pop_back();
    if (!stack.empty())
      stack.back().parts.push_back(made);
  }
  return made;
}

} // namespace

Value writeBack(RewriterBase &rewriter, Location loc, Type type, const Constant &constant,
                Dialect &constants) {
  MLIRContext *context = rewriter.getContext();
  return match(
      constant,
      [&](const Real &real) -> Value {
        APFloat bits(APFloat::IEEEdouble(), APInt(64, real.bits));
        TypedAttr value = FloatAttr::get(type, bits);
        return arith::ConstantOp::create(rewriter, loc, type, value).getResult();
      },
      [&](const Text &text) -> Value {
        return materialized(constants, rewriter, loc, type, fold::strAttr(context, text.get()));
      },
      [&](const Big &big) -> Value {
        return materialized(constants, rewriter, loc, type, fold::bigAttr(context, big.get()));
      },
      [&](const Data &data) -> Value {
        return materialized(constants, rewriter, loc, type, attributeOf(context, data));
      });
}

} // namespace idr::egraph::detail
