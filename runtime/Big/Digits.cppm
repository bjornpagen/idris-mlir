// rt.big:digits: bigs as decimal text, and read from digits of any base.
// PIN(runtime-quarantine) — see PINS.md
module;
#include "idris_rt.h"

#include <stddef.h>
#include <stdint.h>
#include <string.h>

#include <gmp.h>

export module rt.big:digits;

import rt.alloc;
import rt.numerals;
import rt.strings;
import :operands;
import :words;

export namespace rt::big {

// The natural number the n bytes at p write in `base`, digits that
// underscores may separate.
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

extern "C" const idris_rt_str *idris_rt_big_show(idris_rt_big a) {
  using namespace rt::big;
  if (isSmall(a))
    return idris_rt_str_show_s(smallValue(a));
  rt::alloc::gmpReady();
  Operand x(a);
  mpz_srcptr z = x.get();
  size_t room = mpz_sizeinbase(z, 10) + 2;
  idris_rt_str *s = rt::strings::newString(room, 0, true);
  char *text = rt::strings::mutableBytes(s);
  mpz_get_str(text, 10, z);
  s->bytes = strlen(text);
  s->scalars = s->bytes;
  return s;
}

// The integer cast of rt.numerals, exactly: a short decimal on the stack,
// any other through GMP.
extern "C" idris_rt_big idris_rt_big_from_str(const idris_rt_str *s) {
  using namespace rt::big;
  const char *p = idris_rt_str_bytes(s);
  rt::numerals::Numeral numeral = rt::numerals::readNumeral(p, s->bytes);
  if (numeral.kind != rt::numerals::Numeral::Integer)
    return small(0);
  if (numeral.base == 10 && !numeral.grouped && s->bytes - numeral.digits <= 18)
    return ofInt64(static_cast<int64_t>(numeral.wrapped(p, s->bytes)));
  idris_rt_big magnitude = bigOfDigits(p + numeral.digits, s->bytes - numeral.digits, numeral.base);
  if (!numeral.negative)
    return magnitude;
  idris_rt_big value = idris_rt_big_neg(magnitude);
  idris_rt_big_release(magnitude);
  return value;
}
