// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// Bigs as decimal text, as a string and written to standard output with no
// string, and read from digits of any base.
// PIN(runtime-quarantine) — see PINS.md
#include "Alloc/Alloc.h"
#include "Big/Big.h"
#include "Io/Io.h"
#include "Numerals/Numerals.h"
#include "Strings/Strings.h"
#include "idris_rt.h"

#include <concepts>
#include <stddef.h>
#include <stdint.h>
#include <string.h>

#include <gmp.h>

namespace {

// The decimal text of a big no word holds, by GMP, into the room `roomFor`
// gives for the most it may take: the digits, one too many at most, a sign
// and its NUL. Its length; all of it ASCII.
template <std::invocable<size_t> RoomFor>
size_t gmpText(mpz_srcptr z, RoomFor roomFor) {
  char *text = roomFor(mpz_sizeinbase(z, 10) + 2);
  mpz_get_str(text, 10, z);
  return strlen(text);
}

} // namespace

namespace rt::big {

idris_rt_big bigOfDigits(const char *p, size_t n, unsigned base) {
  auto *text = static_cast<char *>(rt::alloc::allocate(n + 1));
  size_t length = 0;
  for (size_t i = 0; i < n; ++i)
    if (p[i] != '_')
      text[length++] = p[i];
  text[length] = '\0';
  Result r;
  mpz_set_str(r.get(), text, static_cast<int>(base));
  rt::alloc::release(text);
  return r.finish();
}

} // namespace rt::big

// A big's decimal text, a new string.
extern "C" const idris_rt_str *idris_rt_big_show(idris_rt_big a) {
  using namespace rt::big;
  if (idris_rt_word_is_small(a))
    return idris_rt_str_show_s(idris_rt_small_value(a));
  Operand x(a);
  idris_rt_str *s = nullptr;
  size_t n = gmpText(x.get(), [&](size_t room) {
    s = rt::strings::newString(room, room);
    return rt::strings::mutableBytes(s);
  });
  s->bytes = s->scalars = n;
  return s;
}

// The same text, written to standard output with no string: a small big's
// as its integer's, any other formatted where it goes, in the output's
// buffer. Only a text longer than the whole buffer is formatted elsewhere,
// in a block as long as it, given back once written: no memory the writer
// holds bounds a big's digits.
extern "C" void idris_rt_io_put_big(idris_rt_big a) {
  using namespace rt::big;
  if (idris_rt_word_is_small(a)) {
    idris_rt_io_put_s(idris_rt_small_value(a));
    return;
  }
  Operand x(a);
  mpz_srcptr z = x.get();
  if (mpz_sizeinbase(z, 10) + 2 <= rt::io::bufferSize) {
    rt::io::outputWritten(gmpText(z, rt::io::outputRoom));
    return;
  }
  char *block = nullptr;
  size_t n = gmpText(z, [&](size_t room) {
    block = static_cast<char *>(rt::alloc::allocate(room));
    return block;
  });
  rt::io::putOutput(block, n);
  rt::alloc::release(block);
}

// `cast` from String to Integer: the integer cast of idris_rt_str_to_int,
// exactly, without the wrapping. A short decimal is read on the stack, any
// other through GMP.
extern "C" idris_rt_big idris_rt_big_from_str(const idris_rt_str *s) {
  using namespace rt::big;
  const char *p = idris_rt_str_bytes(s);
  rt::numerals::Numeral numeral = rt::numerals::readNumeral(p, s->bytes);
  if (numeral.kind != rt::numerals::Numeral::Integer)
    return idris_rt_small_word(0);
  if (numeral.base == 10 && !numeral.grouped && s->bytes - numeral.digits <= 18)
    return ofInt64(static_cast<int64_t>(numeral.wrapped(p, s->bytes)));
  idris_rt_big magnitude = bigOfDigits(p + numeral.digits, s->bytes - numeral.digits, numeral.base);
  if (!numeral.negative)
    return magnitude;
  idris_rt_big value = idris_rt_big_neg(magnitude);
  release(magnitude);
  return value;
}
