// Bigs (LOW-BIG-1; docs/plan.md sections 3 and 5.3): Integer and the
// Nat-like types. A value that fits in 63 bits is a tagged word, and any
// other is a GMP integer, so each integer has one representation; every
// operation returns the small form when the result fits.
//
// Division and modulus are Euclidean: the remainder is in [0, |b|). That is
// blodwen-euclidDiv and blodwen-euclidMod of the Chez support code, which
// Integer's div and mod compile to (`div (Signed Unlimited)` in
// Compiler/Scheme/Common.idr), and what Idris's evaluator computes, through
// the Integer div and mod of the Chez it runs on (SEM-INT-3).
// PIN(runtime-quarantine) — see PINS.md

#include "internal.h"

#include <gmp.h>
#include <string.h>

static_assert(sizeof(mp_limb_t) == sizeof(uint64_t), "a limb is 64 bits");
static_assert(sizeof(__mpz_struct) == 16 && offsetof(idris_rt_bignum, size) == 12 &&
                  offsetof(idris_rt_bignum, limbs) == 16,
              "idris_rt_bignum spells out __mpz_struct after the header");

namespace {

constexpr int64_t smallMin = -(int64_t{1} << 62);
constexpr int64_t smallMax = (int64_t{1} << 62) - 1;

bool isSmall(idris_rt_big a) { return (a & 1) != 0; }
int64_t smallValue(idris_rt_big a) { return a >> 1; }
bool fits(int64_t v) { return v >= smallMin && v <= smallMax; }
idris_rt_big small(int64_t v) {
  return static_cast<idris_rt_big>(static_cast<uint64_t>(v) << 1 | 1);
}

idris_rt_bignum *bignum(idris_rt_big a) { return reinterpret_cast<idris_rt_bignum *>(a); }
mpz_ptr integer(idris_rt_bignum *b) { return reinterpret_cast<mpz_ptr>(&b->alloc); }

// A GMP view of any big: a large one's own integer, or a small one's value
// in one limb on the stack.
struct Operand {
  mp_limb_t limb;
  __mpz_struct view;

  explicit Operand(idris_rt_big a) {
    if (!isSmall(a)) {
      view = *integer(bignum(a));
      return;
    }
    int64_t v = smallValue(a);
    limb = v < 0 ? 0 - static_cast<uint64_t>(v) : static_cast<uint64_t>(v);
    mpz_roinit_n(&view, &limb, v < 0 ? -1 : v > 0 ? 1 : 0);
  }
  mpz_srcptr get() const { return &view; }
};

// A new large big, initialized to 0, for a GMP operation to write.
idris_rt_bignum *fresh() {
  rt::gmpReady();
  auto *b = static_cast<idris_rt_bignum *>(rt::allocate(sizeof(idris_rt_bignum)));
  b->header = {1, 0};
  mpz_init(integer(b));
  return b;
}

// The result of a GMP operation, in its one representation.
idris_rt_big finish(idris_rt_bignum *b) {
  mpz_ptr z = integer(b);
  if (mpz_fits_slong_p(z)) {
    long v = mpz_get_si(z);
    if (fits(v)) {
      mpz_clear(z);
      rt::release(b);
      return small(v);
    }
  }
  return reinterpret_cast<idris_rt_big>(b);
}

idris_rt_big ofInt64(int64_t v) {
  if (fits(v))
    return small(v);
  idris_rt_bignum *b = fresh();
  mpz_set_si(integer(b), v);
  return reinterpret_cast<idris_rt_big>(b);
}

template <typename Op> idris_rt_big binary(idris_rt_big a, idris_rt_big b, Op op) {
  Operand x(a), y(b);
  idris_rt_bignum *r = fresh();
  op(integer(r), x.get(), y.get());
  return finish(r);
}

int32_t signOf(idris_rt_big a) {
  if (isSmall(a))
    return smallValue(a) < 0 ? -1 : smallValue(a) > 0 ? 1 : 0;
  return mpz_sgn(integer(bignum(a)));
}

} // namespace

extern "C" idris_rt_big idris_rt_big_add(idris_rt_big a, idris_rt_big b) {
  if (isSmall(a) && isSmall(b))
    return ofInt64(smallValue(a) + smallValue(b));
  return binary(a, b, mpz_add);
}

extern "C" idris_rt_big idris_rt_big_sub(idris_rt_big a, idris_rt_big b) {
  if (isSmall(a) && isSmall(b))
    return ofInt64(smallValue(a) - smallValue(b));
  return binary(a, b, mpz_sub);
}

extern "C" idris_rt_big idris_rt_big_mul(idris_rt_big a, idris_rt_big b) {
  int64_t product;
  if (isSmall(a) && isSmall(b) && !__builtin_mul_overflow(smallValue(a), smallValue(b), &product))
    return ofInt64(product);
  return binary(a, b, mpz_mul);
}

extern "C" idris_rt_big idris_rt_big_div(idris_rt_big a, idris_rt_big b) {
  if (isSmall(a) && isSmall(b)) {
    int64_t x = smallValue(a), y = smallValue(b);
    int64_t q = x / y;
    if (x % y < 0)
      q = y > 0 ? q - 1 : q + 1;
    return ofInt64(q);
  }
  return binary(a, b, signOf(b) > 0 ? mpz_fdiv_q : mpz_cdiv_q);
}

extern "C" idris_rt_big idris_rt_big_mod(idris_rt_big a, idris_rt_big b) {
  if (isSmall(a) && isSmall(b)) {
    int64_t x = smallValue(a), y = smallValue(b);
    int64_t r = x % y;
    if (r < 0)
      r = y > 0 ? r + y : r - y;
    return small(r);
  }
  return binary(a, b, mpz_mod);
}

extern "C" idris_rt_big idris_rt_big_and(idris_rt_big a, idris_rt_big b) {
  if (isSmall(a) && isSmall(b))
    return small(smallValue(a) & smallValue(b));
  return binary(a, b, mpz_and);
}

extern "C" idris_rt_big idris_rt_big_or(idris_rt_big a, idris_rt_big b) {
  if (isSmall(a) && isSmall(b))
    return small(smallValue(a) | smallValue(b));
  return binary(a, b, mpz_ior);
}

extern "C" idris_rt_big idris_rt_big_xor(idris_rt_big a, idris_rt_big b) {
  if (isSmall(a) && isSmall(b))
    return small(smallValue(a) ^ smallValue(b));
  return binary(a, b, mpz_xor);
}

extern "C" idris_rt_big idris_rt_big_neg(idris_rt_big a) {
  if (isSmall(a))
    return ofInt64(-smallValue(a));
  Operand x(a);
  idris_rt_bignum *r = fresh();
  mpz_neg(integer(r), x.get());
  return finish(r);
}

extern "C" int32_t idris_rt_big_compare(idris_rt_big a, idris_rt_big b) {
  if (isSmall(a) && isSmall(b))
    return smallValue(a) < smallValue(b) ? -1 : smallValue(a) > smallValue(b) ? 1 : 0;
  Operand x(a), y(b);
  int c = mpz_cmp(x.get(), y.get());
  return c < 0 ? -1 : c > 0 ? 1 : 0;
}

extern "C" idris_rt_big idris_rt_big_from_int_s(int64_t value) { return ofInt64(value); }

extern "C" idris_rt_big idris_rt_big_from_int_u(uint64_t value) {
  if (value <= static_cast<uint64_t>(smallMax))
    return small(static_cast<int64_t>(value));
  idris_rt_bignum *b = fresh();
  mpz_set_ui(integer(b), value);
  return reinterpret_cast<idris_rt_big>(b);
}

extern "C" int64_t idris_rt_big_to_int(idris_rt_big a) {
  if (isSmall(a))
    return smallValue(a);
  mpz_srcptr z = integer(bignum(a));
  uint64_t low = mpz_getlimbn(z, 0);
  return static_cast<int64_t>(mpz_sgn(z) < 0 ? 0 - low : low);
}

extern "C" idris_rt_big idris_rt_big_from_double(double x) {
  if (x > -4611686018427387904.0 && x < 4611686018427387904.0)
    return small(static_cast<int64_t>(x));
  idris_rt_bignum *b = fresh();
  mpz_set_d(integer(b), x);
  return finish(b);
}

// GMP's mpz_get_d truncates. The top 64 bits of |a|, with a sticky bit for
// any bit below them, convert with one correct rounding, and the scaling by
// a power of two is exact (or overflows to infinity, as Chez's does).
extern "C" double idris_rt_big_to_double(idris_rt_big a) {
  if (isSmall(a))
    return static_cast<double>(smallValue(a));
  mpz_srcptr z = integer(bignum(a));
  size_t bits = mpz_sizeinbase(z, 2);
  if (bits <= 64) {
    auto magnitude = static_cast<double>(mpz_getlimbn(z, 0));
    return mpz_sgn(z) < 0 ? -magnitude : magnitude;
  }
  size_t shift = bits - 64;
  size_t limb = shift / 64;
  unsigned offset = static_cast<unsigned>(shift % 64);
  uint64_t top = mpz_getlimbn(z, static_cast<mp_size_t>(limb)) >> offset;
  if (offset != 0)
    top |= mpz_getlimbn(z, static_cast<mp_size_t>(limb + 1)) << (64 - offset);
  bool sticky = offset != 0 && (mpz_getlimbn(z, static_cast<mp_size_t>(limb)) &
                                ((uint64_t{1} << offset) - 1)) != 0;
  for (size_t i = 0; i < limb && !sticky; ++i)
    sticky = mpz_getlimbn(z, static_cast<mp_size_t>(i)) != 0;
  double magnitude = __builtin_ldexp(static_cast<double>(top | (sticky ? 1 : 0)),
                                     static_cast<int>(shift));
  return mpz_sgn(z) < 0 ? -magnitude : magnitude;
}

extern "C" const idris_rt_str *idris_rt_big_show(idris_rt_big a) {
  if (isSmall(a))
    return idris_rt_str_show_s(smallValue(a));
  rt::gmpReady();
  mpz_srcptr z = integer(bignum(a));
  size_t room = mpz_sizeinbase(z, 10) + 2;
  idris_rt_str *s = rt::newString(room, 0, true);
  char *text = rt::mutableBytes(s);
  mpz_get_str(text, 10, z);
  s->bytes = strlen(text);
  s->scalars = s->bytes;
  return s;
}

extern "C" idris_rt_big idris_rt_big_from_str(const idris_rt_str *s) {
  const char *p = idris_rt_str_bytes(s);
  size_t digits;
  if (!rt::isInteger(p, s->bytes, digits)) {
    double value = idris_rt_parse_double(p, s->bytes);
    return __builtin_isfinite(value) ? idris_rt_big_from_double(value) : small(0);
  }
  if (s->bytes - digits <= 18) {
    int64_t value = 0;
    for (size_t i = digits; i < s->bytes; ++i)
      value = 10 * value + (p[i] - '0');
    return ofInt64(p[0] == '-' ? -value : value);
  }
  rt::gmpReady();
  auto *text = static_cast<char *>(rt::allocate(s->bytes + 1));
  memcpy(text, p, s->bytes);
  text[s->bytes] = '\0';
  idris_rt_bignum *b = fresh();
  mpz_set_str(integer(b), text + (p[0] == '+' ? 1 : 0), 10);
  rt::release(text);
  return finish(b);
}

extern "C" void idris_rt_big_release(idris_rt_big a) {
  if (isSmall(a) || bignum(a)->header.count == 0)
    return;
  mpz_clear(integer(bignum(a)));
  rt::release(bignum(a));
}
