// Bigs: Integer and the
// Nat-like types. A value that fits in 63 bits is a tagged word, and any
// other is a GMP integer, so each integer has one representation; every
// operation returns the small form when the result fits.
//
// Division and modulus are Euclidean: the remainder is in [0, |b|). That is
// blodwen-euclidDiv and blodwen-euclidMod of the Chez support code, which
// Integer's div and mod compile to (`div (Signed Unlimited)` in
// Compiler/Scheme/Common.idr), and what Idris's evaluator computes, through
// the Integer div and mod of the Chez it runs on.
// PIN(runtime-quarantine) — see PINS.md

#include "internal.h"

#include <gmp.h>
#include <string.h>

static_assert(sizeof(mp_limb_t) == sizeof(uint64_t), "a limb is 64 bits");
static_assert(sizeof(idris_rt_bignum) == 16 && alignof(idris_rt_bignum) == 8,
              "a bignum's limbs start 16 bytes into its cell, aligned for a limb");
// A large big's word is its cell's address itself: cells are 8-aligned, so
// the address is even, which is the whole tag, and no other bit of the word
// is borrowed. Hardware that prefetches what looks like a heap pointer
// (Apple's and Intel's data-dependent prefetchers) then follows it.
static_assert(sizeof(idris_rt_big) == sizeof(void *) && alignof(idris_rt_header) % 2 == 0,
              "an even big word is exactly a cell address");

namespace {

constexpr int64_t smallMin = -(int64_t{1} << 62);
constexpr int64_t smallMax = (int64_t{1} << 62) - 1;

bool isSmall(idris_rt_big a) { return (a & 1) != 0; }
int64_t smallValue(idris_rt_big a) { return a >> 1; }
bool fits(int64_t v) { return v >= smallMin && v <= smallMax; }
idris_rt_big small(int64_t v) {
  return static_cast<idris_rt_big>(static_cast<uint64_t>(v) << 1 | 1);
}

const idris_rt_bignum *bignum(idris_rt_big a) {
  return reinterpret_cast<const idris_rt_bignum *>(a);
}
// The limbs follow the bignum in its cell.
const mp_limb_t *limbsOf(const idris_rt_bignum *b) {
  return reinterpret_cast<const mp_limb_t *>(b + 1);
}

// A read-only GMP view of any big, which copies nothing: a large one's limbs
// in its cell, or a small one's value in one limb on the stack.
struct Operand {
  mp_limb_t limb;
  __mpz_struct view;

  explicit Operand(idris_rt_big a) {
    if (!isSmall(a)) {
      const idris_rt_bignum *b = bignum(a);
      mpz_roinit_n(&view, limbsOf(b), static_cast<mp_size_t>(b->size));
      return;
    }
    int64_t v = smallValue(a);
    limb = v < 0 ? 0 - static_cast<uint64_t>(v) : static_cast<uint64_t>(v);
    mpz_roinit_n(&view, &limb, v < 0 ? -1 : v > 0 ? 1 : 0);
  }
  mpz_srcptr get() const { return &view; }
};

// The integer a GMP operation writes, on the stack. finish gives it its one
// representation: a small word, or, only when it does not fit one, a new
// cell of exactly its size that its limbs are copied into, so a small result
// allocates no cell and a large one allocates one.
class Result {
public:
  Result() {
    rt::gmpReady();
    mpz_init(&value);
  }
  Result(const Result &) = delete;
  Result &operator=(const Result &) = delete;

  mpz_ptr get() { return &value; }

  idris_rt_big finish() {
    if (mpz_fits_slong_p(&value) && fits(mpz_get_si(&value))) {
      int64_t v = mpz_get_si(&value);
      mpz_clear(&value);
      return small(v);
    }
    size_t count = mpz_size(&value);
    auto *b = static_cast<idris_rt_bignum *>(rt::newCell(
        sizeof(idris_rt_bignum) + count * sizeof(mp_limb_t), idris_rt_info(0, 0, IDRIS_RT_KIND_BIGNUM)));
    auto size = static_cast<int64_t>(count);
    b->size = mpz_sgn(&value) < 0 ? -size : size;
    memcpy(b + 1, mpz_limbs_read(&value), count * sizeof(mp_limb_t));
    mpz_clear(&value);
    return reinterpret_cast<idris_rt_big>(b);
  }

private:
  __mpz_struct value;
};

idris_rt_big ofInt64(int64_t v) {
  if (fits(v))
    return small(v);
  Result r;
  mpz_set_si(r.get(), v);
  return r.finish();
}

template <typename Op> idris_rt_big binary(idris_rt_big a, idris_rt_big b, Op op) {
  Operand x(a), y(b);
  Result r;
  op(r.get(), x.get(), y.get());
  return r.finish();
}

int32_t signOf(idris_rt_big a) {
  if (isSmall(a))
    return smallValue(a) < 0 ? -1 : smallValue(a) > 0 ? 1 : 0;
  int64_t size = bignum(a)->size;
  return size < 0 ? -1 : size > 0 ? 1 : 0;
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

extern "C" idris_rt_big idris_rt_big_pred(idris_rt_big a) {
  return idris_rt_big_sub(a, small(1));
}

// A negative integer is 0, as Idris's integerToNat; any other is itself,
// with one more reference, since the result is owned.
extern "C" idris_rt_big idris_rt_nat_from_big(idris_rt_big a) {
  if (signOf(a) < 0)
    return small(0);
  if (!isSmall(a))
    idris_rt_inc(reinterpret_cast<void *>(a));
  return a;
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
  Result r;
  mpz_neg(r.get(), x.get());
  return r.finish();
}

extern "C" int32_t idris_rt_big_cmp(idris_rt_big a, idris_rt_big b) {
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
  Result r;
  mpz_set_ui(r.get(), value);
  return r.finish();
}

extern "C" int64_t idris_rt_big_to_int(idris_rt_big a) {
  if (isSmall(a))
    return smallValue(a);
  Operand x(a);
  uint64_t low = mpz_getlimbn(x.get(), 0);
  return static_cast<int64_t>(mpz_sgn(x.get()) < 0 ? 0 - low : low);
}

extern "C" idris_rt_big idris_rt_big_from_double(double x) {
  if (x > -4611686018427387904.0 && x < 4611686018427387904.0)
    return small(static_cast<int64_t>(x));
  Result r;
  mpz_set_d(r.get(), x);
  return r.finish();
}

// GMP's mpz_get_d truncates. The top 64 bits of |a|, with a sticky bit for
// any bit below them, convert with one correct rounding, and the scaling by
// a power of two is exact (or overflows to infinity, as Chez's does).
extern "C" double idris_rt_big_to_double(idris_rt_big a) {
  if (isSmall(a))
    return static_cast<double>(smallValue(a));
  Operand x(a);
  mpz_srcptr z = x.get();
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
  Operand x(a);
  mpz_srcptr z = x.get();
  size_t room = mpz_sizeinbase(z, 10) + 2;
  idris_rt_str *s = rt::newString(room, 0, true);
  char *text = rt::mutableBytes(s);
  mpz_get_str(text, 10, z);
  s->bytes = strlen(text);
  s->scalars = s->bytes;
  return s;
}

idris_rt_big rt::bigOfDigits(const char *p, size_t n, unsigned base) {
  auto *text = static_cast<char *>(rt::allocate(n + 1));
  size_t length = 0;
  for (size_t i = 0; i < n; ++i)
    if (p[i] != '_')
      text[length++] = p[i];
  text[length] = '\0';
  Result r;
  mpz_set_str(r.get(), text, static_cast<int>(base));
  rt::release(text);
  return r.finish();
}

// The integer cast of numbers.cc, exactly: a short decimal on the stack,
// any other through GMP.
extern "C" idris_rt_big idris_rt_big_from_str(const idris_rt_str *s) {
  const char *p = idris_rt_str_bytes(s);
  rt::Numeral numeral = rt::readNumeral(p, s->bytes);
  if (numeral.kind != rt::Numeral::Integer)
    return small(0);
  if (numeral.base == 10 && !numeral.grouped && s->bytes - numeral.digits <= 18)
    return ofInt64(static_cast<int64_t>(numeral.wrapped(p, s->bytes)));
  idris_rt_big magnitude = rt::bigOfDigits(p + numeral.digits, s->bytes - numeral.digits, numeral.base);
  if (!numeral.negative)
    return magnitude;
  idris_rt_big value = idris_rt_big_neg(magnitude);
  idris_rt_big_release(magnitude);
  return value;
}

extern "C" void idris_rt_big_release(idris_rt_big a) {
  idris_rt_dec(reinterpret_cast<void *>(a));
}
