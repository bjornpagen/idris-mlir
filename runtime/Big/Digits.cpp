// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// Bigs as decimal text, and read from digits of any base.
// PIN(runtime-quarantine) — see PINS.md
#include "Alloc/Alloc.h"
#include "Big/Big.h"
#include "Numerals/Numerals.h"
#include "Strings/Strings.h"
#include "idris_rt.h"

#include <stddef.h>
#include <stdint.h>
#include <string.h>

#include <gmp.h>

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
  mpz_srcptr z = x.get();
  // Room for the digits GMP may write, one too many at most, a sign and its
  // NUL; the lengths are then its text's, all ASCII.
  size_t room = mpz_sizeinbase(z, 10) + 2;
  idris_rt_str *s = rt::strings::newString(room, room);
  char *text = rt::strings::mutableBytes(s);
  mpz_get_str(text, 10, z);
  s->bytes = s->scalars = strlen(text);
  return s;
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
