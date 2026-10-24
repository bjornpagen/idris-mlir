// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The runtime references one fold holds, and the strings and bigs a fold
// converts. A string's bytes cross as they are. A big constant and the
// runtime's big are one integer in two layouts, the attribute's APInt words
// and the runtime's word or bignum cell (idris_rt.h), so a crossing copies
// words: the integer is never printed and parsed back.

#include "idr/IR/IdrDialect.h"
#include "idr/IR/Fold.h"

#include "mlir/IR/BuiltinAttributes.h"
#include "mlir/IR/MLIRContext.h"
#include "llvm/ADT/APInt.h"
#include "llvm/ADT/ArrayRef.h"

#include <algorithm>
#include <concepts>
#include <cstdint>

using namespace mlir;

namespace idr::fold {

namespace {

// A large big's limbs follow its bignum in the cell, least significant
// first, each one of APInt's words.
static_assert(std::same_as<APInt::WordType, uint64_t>, "a limb is one of APInt's words");

const uint64_t *limbsOf(const idris_rt_bignum *number) {
  return reinterpret_cast<const uint64_t *>(number + 1);
}

uint64_t *limbsOf(idris_rt_bignum *number) { return reinterpret_cast<uint64_t *>(number + 1); }

} // namespace

// Each reference is released by the runtime's entry of its word's kind: a
// string's word is always its cell, given as the cell's header, a big's a
// small or a cell. A string's bytes are immutable; its count, in its
// header, is the one word a release writes.
Scope::~Scope() {
  for (const idris_rt_str *s : strings)
    idris_rt_dec_cell(&const_cast<idris_rt_str *>(s)->header);
  for (idris_rt_big b : bigs)
    idris_rt_dec_big(b);
}

const idris_rt_str *Scope::keep(const idris_rt_str *s) {
  strings.push_back(s);
  return s;
}

idris_rt_big Scope::keep(idris_rt_big b) {
  bigs.push_back(b);
  return b;
}

std::optional<const idris_rt_str *> strOf(Scope &scope, Attribute constant) {
  auto text = dyn_cast_or_null<StringAttr>(constant);
  if (!text)
    return std::nullopt;
  return scope.keep(idris_rt_str_from_utf8(text.data(), text.size()));
}

// The integer in the one representation the runtime gives it: its word when
// it is in the small range, a word no reference holds; any other a new
// bignum cell of its magnitude's words and its sign, which the scope keeps.
// The magnitude, read unsigned at the integer's own width, is exact even for
// that width's least value, whose negation is itself; its top word is not
// zero, as the runtime's every bignum has it.
std::optional<idris_rt_big> bigOf(Scope &scope, Attribute constant) {
  auto big = dyn_cast_or_null<BigAttr>(constant);
  if (!big)
    return std::nullopt;
  const APInt &value = big.getValue();
  std::optional<int64_t> word = value.trySExtValue();
  if (word && *word >= IDRIS_RT_SMALL_MIN && *word <= IDRIS_RT_SMALL_MAX)
    return runtime::Abi<BigSmallOp>::function(*word);
  APInt magnitude = value.abs();
  unsigned count = magnitude.getActiveWords();
  auto *number = reinterpret_cast<idris_rt_bignum *>(
      idris_rt_cell(static_cast<int64_t>(sizeof(idris_rt_bignum) + count * sizeof(uint64_t)),
                    static_cast<int32_t>(idris_rt_info(0, 0, IDRIS_RT_KIND_BIGNUM))));
  number->size = value.isNegative() ? -static_cast<int64_t>(count) : static_cast<int64_t>(count);
  std::copy_n(magnitude.getRawData(), count, limbsOf(number));
  return scope.keep(reinterpret_cast<idris_rt_big>(number));
}

Attribute strAttr(MLIRContext *context, const idris_rt_str *s) {
  return StringAttr::get(context, StringRef(idris_rt_str_bytes(s), s->bytes));
}

// A small word's value, or a bignum's limbs read as its magnitude at one bit
// more than they fill, so that its sign, applied by negation, fits. The
// attribute keys the integer at its fewest signed bits.
Attribute bigAttr(MLIRContext *context, idris_rt_big b) {
  if (idris_rt_word_is_small(b))
    return BigAttr::get(context, APInt(64, static_cast<uint64_t>(idris_rt_small_value(b)),
                                       /*isSigned=*/true));
  const auto *number = reinterpret_cast<const idris_rt_bignum *>(b);
  auto count = static_cast<unsigned>(number->size < 0 ? -number->size : number->size);
  APInt magnitude(count * APInt::APINT_BITS_PER_WORD + 1,
                  ArrayRef<uint64_t>(limbsOf(number), count));
  return BigAttr::get(context, number->size < 0 ? -magnitude : magnitude);
}

} // namespace idr::fold
