// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The runtime's bigs held to their meaning in idris_rt.h: each operation
// against what GMP's arithmetic states it is (the integer, a defining
// property, a bit-by-bit restatement, an exact comparison), laws between the
// operations, each entry's small path against its large one, the edges
// exhaustively, and ownership. Operands are persistent constants in the
// documented layout (bigmodel.h), and results are read back from it.
#include "bigmodel.h"
#include "idris_rt.h"
#include "prop.h"
// The large paths of the runtime's bigs, which each entry tail-calls when
// an operand is large or a result leaves the small range, and which take
// any bigs, small ones included: declared by the runtime's own header,
// reached through its include directory, and linked from its archive.
#include <Big/Big.h>

#include <gmp.h>
#include <math.h>
#include <stddef.h>
#include <stdint.h>
#include <string.h>

namespace {

using bigmodel::explainValues;
using bigmodel::low64;
using bigmodel::Operand;
using bigmodel::Result;
using bigmodel::Z;

// A rational of the test's, exact, its fields read as Z's are.
class Q {
public:
  Q() { mpq_init(q_); }
  ~Q() { mpq_clear(q_); }
  Q(const Q &) = delete;
  Q &operator=(const Q &) = delete;
  operator mpq_ptr() { return q_; }
  operator mpq_srcptr() const { return q_; }
  mpq_ptr operator->() { return q_; }
  mpq_srcptr operator->() const { return q_; }

private:
  mpq_t q_;
};

// r is canonical and is the integer `want`.
bool is(const char *what, const Result &r, mpz_srcptr want) {
  bool shaped = bigmodel::canonical(r.word());
  bool equal = mpz_cmp(r.value(), want) == 0;
  if (!shaped || !equal)
    explainValues("%s gives %#Zx, where %#Zx is the integer", what, r.value(), want);
  return shaped && equal;
}

// x and y are the same integer, each canonical.
bool same(const char *what, idris_rt_big x, idris_rt_big y) {
  Z xv, yv;
  bigmodel::value(x, xv);
  bigmodel::value(y, yv);
  // Both are checked, each explaining itself.
  bool xShaped = bigmodel::canonical(x), yShaped = bigmodel::canonical(y);
  bool shaped = xShaped && yShaped;
  bool equal = mpz_cmp(xv, yv) == 0;
  if (!shaped || !equal)
    explainValues("%s: %#Zx and %#Zx", what, static_cast<mpz_srcptr>(xv), static_cast<mpz_srcptr>(yv));
  return shaped && equal;
}

int signOf(long c) { return (c > 0) - (c < 0); }

// A case's class: the forms of its words, by their tag bits (an odd word is
// small, an even one a cell), in the order its property names them.
const char *formsOf(idris_rt_big x, idris_rt_big y) {
  static constexpr const char *names[] = {"large large", "large small", "small large", "small small"};
  return names[static_cast<unsigned>(x & 1) << 1 | static_cast<unsigned>(y & 1)];
}
const char *formsOf(idris_rt_big x, idris_rt_big y, idris_rt_big z) {
  static constexpr const char *names[] = {"large large large", "large large small", "large small large",
                                          "large small small", "small large large", "small large small",
                                          "small small large", "small small small"};
  return names[static_cast<unsigned>(x & 1) << 2 | static_cast<unsigned>(y & 1) << 1 |
               static_cast<unsigned>(z & 1)];
}

// A big drawn from one of the families the case's swarm mask keeps, and
// said, for the case's explanation.
void drawBig(FuzzedDataProvider &p, uint64_t mask, mpz_ptr out, const char *name) {
  bigmodel::draw(p, prop::pick(p, mask), out);
  explainValues("%s = %#Zx", name, static_cast<mpz_srcptr>(out));
}

using Binary = idris_rt_big (*)(idris_rt_big, idris_rt_big);
using Unary = idris_rt_big (*)(idris_rt_big);

// add, sub, mul: each entry, its large path, and the integer GMP computes.
struct Arithmetic {
  const char *name;
  Binary entry, large;
  void (*integer)(mpz_ptr, mpz_srcptr, mpz_srcptr);
};
constexpr Arithmetic arithmetic[] = {{"add", idris_rt_big_add, rt::big::addLarge, mpz_add},
                                     {"sub", idris_rt_big_sub, rt::big::subLarge, mpz_sub},
                                     {"mul", idris_rt_big_mul, rt::big::mulLarge, mpz_mul}};

// and, or, xor: each entry, its large path, and what it does to one bit.
struct Bitwise {
  const char *name;
  Binary entry, large;
  int (*bit)(int, int);
};
constexpr Bitwise bitwise[] = {
    {"and", idris_rt_big_and, rt::big::andLarge, [](int x, int y) { return x & y; }},
    {"or", idris_rt_big_or, rt::big::orLarge, [](int x, int y) { return x | y; }},
    {"xor", idris_rt_big_xor, rt::big::xorLarge, [](int x, int y) { return x ^ y; }}};

// shl, shr: each entry, its large path, and the way a positive amount moves
// a value, as a power of two: up (1) or down (-1).
struct Shift {
  const char *name;
  Binary entry, large;
  long way;
};
constexpr Shift shifts[] = {{"shl", idris_rt_big_shl, rt::big::shlLarge, 1},
                            {"shr", idris_rt_big_shr, rt::big::shrLarge, -1}};

// neg, nat_from_big: each entry and its large path.
struct Single {
  const char *name;
  Unary entry, large;
};
constexpr Single singles[] = {{"neg", idris_rt_big_neg, rt::big::negLarge},
                              {"nat_from_big", idris_rt_nat_from_big, rt::big::natFromBigLarge}};

// 1. Each of add, sub and mul is the integer GMP computes.
bool sums(const Operand &a, const Operand &b, prop::Tally &tally) {
  bool ok = true;
  for (const Arithmetic &op : arithmetic) {
    Result r(op.entry(a.word(), b.word()));
    Z want;
    op.integer(want, a.value(), b.value());
    ok &= is(op.name, r, want);
    tally.classify(formsOf(a.word(), b.word(), r.word()));
  }
  return ok;
}

// The divisor div and mod are given: idr-lower checks that it is not zero
// before the call, so a drawn zero stands for 1.
void divisorOf(mpz_srcptr drawn, mpz_ptr out) {
  mpz_set(out, drawn);
  mpz_add_ui(out, out, mpz_sgn(out) == 0);
}

// 2. div and mod are Euclidean: a = q*b + r and 0 <= r < |b|, which no
// other pair satisfies.
bool division(const Operand &a, const Operand &drawn, prop::Tally &tally) {
  Z d;
  divisorOf(drawn.value(), d);
  Operand b(d);
  Result q(idris_rt_big_div(a.word(), b.word())), r(idris_rt_big_mod(a.word(), b.word()));
  bool qShaped = bigmodel::canonical(q.word()), rShaped = bigmodel::canonical(r.word());
  bool shaped = qShaped && rShaped;
  Z sum, magnitude;
  mpz_mul(sum, q.value(), b.value());
  mpz_add(sum, sum, r.value());
  mpz_abs(magnitude, b.value());
  bool euclidean = mpz_cmp(sum, a.value()) == 0 && mpz_sgn(r.value()) >= 0 && mpz_cmp(r.value(), magnitude) < 0;
  if (!shaped || !euclidean)
    explainValues("div and mod by %#Zx give %#Zx and %#Zx", b.value(), q.value(), r.value());
  tally.classify(formsOf(a.word(), b.word(), q.word()));
  return shaped && euclidean;
}

// 3. and, or and xor are those of two's complement: each bit of the result
// is the operation on the operands' bits, for every bit up to past the
// widest, and its sign is the operation on their signs, so the bits above,
// all copies of the sign, agree too. mpz_tstbit reads a negative value's
// bits in two's complement.
bool bits(const Operand &a, const Operand &b, prop::Tally &tally) {
  bool ok = true;
  for (const Bitwise &op : bitwise) {
    Result r(op.entry(a.word(), b.word()));
    ok &= bigmodel::canonical(r.word());
    size_t width = mpz_sizeinbase(a.value(), 2);
    width = width > mpz_sizeinbase(b.value(), 2) ? width : mpz_sizeinbase(b.value(), 2);
    width = width > mpz_sizeinbase(r.value(), 2) ? width : mpz_sizeinbase(r.value(), 2);
    for (mp_bitcnt_t i = 0; i < width + 2; ++i)
      if (mpz_tstbit(r.value(), i) != op.bit(mpz_tstbit(a.value(), i), mpz_tstbit(b.value(), i))) {
        explainValues("%s gives %#Zx, whose bit %lu is not the operands'", op.name, r.value(), i);
        ok = false;
        break;
      }
    bool negative = op.bit(mpz_sgn(a.value()) < 0, mpz_sgn(b.value()) < 0) != 0;
    if ((mpz_sgn(r.value()) < 0) != negative) {
      explainValues("%s gives %#Zx, whose sign is not the operands'", op.name, r.value());
      ok = false;
    }
    tally.classify(formsOf(a.word(), b.word(), r.word()));
  }
  return ok;
}

// The largest move up a property makes, as a power of two: the shift
// families' 200, whose product the oracle computes.
constexpr unsigned long upLimit = 200;

// A move by 2^e (e up when positive) that the runtime defines and the test
// computes: toward zero, any; up, as far as upLimit; any of 0. A left shift
// past what an integer can hold ends the process, as exhausted memory does.
bool defined(mpz_srcptr a, mpz_srcptr e) { return mpz_cmp_ui(e, upLimit) <= 0 || mpz_sgn(a) == 0; }

// r = floor(a * 2^e), as r * 2^m <= a * 2^p < (r + 1) * 2^m, where p and m
// are e's parts above and below 0. 0 moved any way is 0, so its p is 0; a
// value moved down past its every bit is its sign, 0 or -1, so m stops at
// one past a's width.
bool moved(const char *what, const Result &r, mpz_srcptr a, mpz_srcptr e) {
  unsigned long p = mpz_sgn(e) > 0 && mpz_sgn(a) != 0 ? mpz_get_ui(e) : 0;
  Z down;
  mpz_neg(down, e);
  unsigned long width = mpz_sizeinbase(a, 2) + 1;
  unsigned long m = mpz_sgn(down) <= 0 ? 0 : mpz_cmp_ui(down, width) > 0 ? width : mpz_get_ui(down);
  Z unit, low, high, scaled;
  mpz_ui_pow_ui(unit, 2, m);
  mpz_mul(low, r.value(), unit);
  mpz_add_ui(high, r.value(), 1);
  mpz_mul(high, high, unit);
  mpz_ui_pow_ui(scaled, 2, p);
  mpz_mul(scaled, scaled, a);
  bool shaped = bigmodel::canonical(r.word());
  bool floor = mpz_cmp(low, scaled) <= 0 && mpz_cmp(scaled, high) < 0;
  if (!shaped || !floor)
    explainValues("%s by 2^%Zd gives %#Zx", what, e, r.value());
  return shaped && floor;
}

// Each shift the runtime defines of a by amount, with the move it makes
// as a power of two: the one place the shifts' domain is kept, since an
// amount the runtime does not define is no input.
template <typename Each> void definedShifts(mpz_srcptr a, mpz_srcptr amount, Each each) {
  for (const Shift &op : shifts) {
    Z e;
    mpz_mul_si(e, amount, op.way);
    if (defined(a, e))
      each(op, static_cast<mpz_srcptr>(e));
  }
}

// 4. A shift by k moves a value by 2^k, shl up and shr down, the other way
// for k < 0: a * 2^k, and the floor of a / 2^k, which fills with the sign.
bool shiftsBy(const Operand &a, const Operand &amount) {
  bool ok = true;
  definedShifts(a.value(), amount.value(), [&](const Shift &op, mpz_srcptr e) {
    Result r(op.entry(a.word(), amount.word()));
    ok &= moved(op.name, r, a.value(), e);
  });
  return ok;
}

// The amounts a shift is drawn by, simplest first: [0, 63), what a small
// word itself shifts by; 60 to 66, across a word's width; up to +-200, past
// three limbs either way; a negative one, the other way; and a large big,
// at least 2^62, by which only a shift toward zero is defined (defined()
// keeps that direction). The last is the only unbounded one.
constexpr unsigned shiftFamilies = 5;
constexpr unsigned boundedShiftFamilies = shiftFamilies - 1;
constexpr const char *shiftNames[shiftFamilies] = {"by [0, 63)", "by 60 to 66", "by -200 to 200", "by a negative",
                                                   "by a large big"};
void drawShift(FuzzedDataProvider &p, unsigned family, mpz_ptr out) {
  switch (family) {
  case 0:
    mpz_set_ui(out, p.ConsumeIntegralInRange<unsigned long>(0, 62));
    break;
  case 1:
    mpz_set_ui(out, p.ConsumeIntegralInRange<unsigned long>(60, 66));
    break;
  case 2:
    mpz_set_ui(out, p.ConsumeIntegralInRange<unsigned long>(0, upLimit));
    mpz_mul_si(out, out, p.ConsumeBool() ? -1 : 1);
    break;
  case 3:
    mpz_set_si(out, -p.ConsumeIntegralInRange<long>(1, upLimit));
    break;
  default:
    // Any big's magnitude with bit 62 set: at least 2^62, no wider than
    // the big, so a constant still holds it.
    bigmodel::draw(p, p.ConsumeIntegralInRange<unsigned>(0, bigmodel::families - 1), out);
    mpz_abs(out, out);
    mpz_setbit(out, 62);
    mpz_mul_si(out, out, p.ConsumeBool() ? -1 : 1);
    break;
  }
  explainValues("amount = %Zd", static_cast<mpz_srcptr>(out));
}

// 5. neg is -a; cmp has the sign of a - b; nat_from_big is 0 for a
// negative a, else a; pred is n - 1 for a natural n above 0, here |a| with
// 0 moved to 1, its domain.
bool order(const Operand &a, const Operand &b, prop::Tally &tally) {
  Result negated(idris_rt_big_neg(a.word()));
  Z minus;
  mpz_neg(minus, a.value());
  bool ok = is("neg", negated, minus);
  int compared = idris_rt_big_cmp(a.word(), b.word());
  if (signOf(compared) != signOf(mpz_cmp(a.value(), b.value()))) {
    prop::explain("cmp gives %d", compared);
    ok = false;
  }
  Result natural(idris_rt_nat_from_big(a.word()));
  Z clamped;
  mpz_mul_ui(clamped, a.value(), mpz_sgn(a.value()) > 0);
  ok &= is("nat_from_big", natural, clamped);
  Z nv;
  mpz_abs(nv, a.value());
  mpz_add_ui(nv, nv, mpz_sgn(nv) == 0);
  Operand n(nv);
  Result before(idris_rt_big_pred(n.word()));
  Z less;
  mpz_sub_ui(less, n.value(), 1);
  ok &= is("pred", before, less);
  tally.classify(formsOf(a.word(), b.word(), negated.word()));
  return ok;
}

// 6. from_int_s and from_int_u give the integer a word is, signed or not;
// to_int gives a's low 64 bits, two's complement.
bool machine(const Operand &a, prop::Tally &tally) {
  uint64_t u = low64(a.value());
  auto x = static_cast<int64_t>(u);
  Result s(idris_rt_big_from_int_s(x)), n(idris_rt_big_from_int_u(u));
  Z signedValue(x), unsignedValue;
  mpz_set_ui(unsignedValue, u);
  bool ok = is("from_int_s", s, signedValue);
  ok &= is("from_int_u", n, unsignedValue);
  int64_t wrapped = idris_rt_big_to_int(a.word());
  if (static_cast<uint64_t>(wrapped) != u) {
    prop::explain("to_int gives %lld", static_cast<long long>(wrapped));
    ok = false;
  }
  tally.classify(formsOf(a.word(), s.word(), n.word()));
  return ok;
}

// x as an exact rational, an infinity as 2^1024 of its sign: IEEE 754
// rounds as though the exponent went on, so that past the largest double
// the next is 2^1024, and a value at least halfway to it, a tie included,
// rounds to infinity, 2^1024's significand being even.
void exactly(double x, mpq_ptr out) {
  // The one double past the finite ones, which mpq_set_d does not take.
  if (isinf(x)) {
    Z power;
    bigmodel::nearPower(power, x < 0 ? -1 : 1, 1024, 0);
    mpq_set_z(out, power);
    return;
  }
  mpq_set_d(out, x);
}

// |a - x|.
void gap(mpq_ptr out, mpq_srcptr a, double x) {
  exactly(x, out);
  mpq_sub(out, a, out);
  mpq_abs(out, out);
}

// 7. to_double is the double nearest a, of two equally near the one whose
// significand is even, and infinity past the largest: no double, 2^1024
// standing for infinity, is nearer than d, and on a tie with a neighbour d
// is even. a is any big, read from its layout.
bool nearest(idris_rt_big word, prop::Tally &tally) {
  Q a;
  {
    Z v;
    bigmodel::value(word, v);
    mpq_set_z(a, v);
  }
  double d = idris_rt_big_to_double(word);
  // NaN is near no integer.
  if (d != d) {
    prop::explain("to_double gives NaN");
    return false;
  }
  Q off;
  gap(off, a, d);
  static constexpr double directions[] = {-INFINITY, INFINITY};
  bool near = true, tie = false;
  for (double direction : directions) {
    double neighbour = nextafter(d, direction);
    Q other;
    gap(other, a, neighbour);
    int c = mpq_cmp(off, other);
    near &= c <= 0;
    // An infinity is its own neighbour outward.
    tie |= c == 0 && neighbour != d;
  }
  bool even = (__builtin_bit_cast(uint64_t, d) & 1) == 0;
  if (!near || (tie && !even))
    prop::explain("to_double gives %a, which is not the nearest%s", d, near ? " even double" : " double");
  tally.classify(isinf(d) ? "infinity" : mpq_sgn(off) == 0 ? "exact" : tie ? "tie" : "rounded");
  return near && (!tie || even);
}

// to_double's operands past bigmodel's, which a constant cannot hold, made
// by shifting one up and read back from their layout, so no runtime result
// stands under the oracle: one 1022 to 1025 bits wide, around the largest
// double's width; one within 2^(970 - j) of 2^1024 - 2^970, halfway from
// the largest double to 2^1024, where the rounding turns to infinity; and
// a tie at any scale, halfway between two doubles, or one off it, below
// its last place, where only a sticky bit tells it from the tie.
constexpr unsigned wideFamilies = bigmodel::families + 3;
// The shift that moves the drawn constant c into family's range.
unsigned long widen(FuzzedDataProvider &p, unsigned family, mpz_ptr c) {
  static constexpr long deltas[] = {0, -1, 1};
  switch (family) {
  case bigmodel::families: {
    bigmodel::draw(p, p.ConsumeIntegralInRange<unsigned>(0, bigmodel::families - 1), c);
    mpz_add_ui(c, c, mpz_sgn(c) == 0);
    return p.ConsumeIntegralInRange<unsigned long>(1022, 1025) - mpz_sizeinbase(c, 2);
  }
  case bigmodel::families + 1: {
    // (2^54 - 1) * 2^j + delta, delta one of -1, 0, 1, moved up by 970 - j.
    unsigned long j = p.ConsumeIntegralInRange<unsigned long>(0, 400);
    bigmodel::nearPower(c, 1, 54 + j, p.PickValueInArray(deltas));
    Z low;
    mpz_setbit(low, j);
    mpz_sub(c, c, low);
    mpz_mul_si(c, c, p.ConsumeBool() ? -1 : 1);
    return 970 - j;
  }
  case bigmodel::families + 2: {
    // h * 2^j + delta, h an odd 54-bit integer, which a double's 53 bits
    // hold only to a tie.
    unsigned long j = p.ConsumeIntegralInRange<unsigned long>(0, 400);
    Z h, delta(p.PickValueInArray(deltas));
    mpz_set_ui(h, p.ConsumeIntegralInRange<unsigned long>(0, (1ul << 52) - 1) << 1 | 1);
    mpz_setbit(h, 53);
    mpz_mul_2exp(c, h, j);
    mpz_add(c, c, delta);
    mpz_mul_si(c, c, p.ConsumeBool() ? -1 : 1);
    return p.ConsumeIntegralInRange<unsigned long>(0, 500);
  }
  default:
    bigmodel::draw(p, family, c);
    return 0;
  }
}

// 8. from_double truncates toward zero: |r| <= |x| < |r| + 1, and r is 0
// or has x's sign. x is finite, as idr-lower checks before the call.
bool truncated(double x, prop::Tally &tally) {
  Result r(idris_rt_big_from_double(x));
  Q xq, rq, ax, ar, above, one;
  mpq_set_d(xq, x);
  mpq_set_z(rq, r.value());
  mpq_abs(ax, xq);
  mpq_abs(ar, rq);
  mpq_set_ui(one, 1, 1);
  mpq_add(above, ar, one);
  bool shaped = bigmodel::canonical(r.word());
  bool within = mpq_cmp(ar, ax) <= 0 && mpq_cmp(ax, above) < 0;
  bool sign = mpz_sgn(r.value()) == 0 || (mpz_sgn(r.value()) < 0) == (x < 0);
  if (!shaped || !within || !sign)
    explainValues("from_double of %a gives %Zd", x, r.value());
  static constexpr const char *names[] = {"large, fractional", "large, integral", "small, fractional",
                                          "small, integral"};
  tally.classify(names[static_cast<unsigned>(r.word() & 1) << 1 |
                       static_cast<unsigned>(mpz_cmp_ui(mpq_denref(xq), 1) == 0)]);
  return shaped && within && sign;
}

// The doubles from_double is drawn on, simplest first: eighths up to 1000;
// any finite one, of every exponent; and those within 4 steps of 2^62,
// where the small range ends, of 2^63 and of 2^64.
constexpr unsigned doubleFamilies = 3;
double drawDouble(FuzzedDataProvider &p, unsigned family) {
  double magnitude;
  switch (family) {
  case 0:
    magnitude = p.ConsumeIntegralInRange<int>(0, 8000) / 8.0;
    break;
  case 1: {
    // Exponent fields 0 to 2046: 2047 is the infinities' and NaN's.
    uint64_t exponent = p.ConsumeIntegralInRange<uint64_t>(0, 2046);
    uint64_t fraction = p.ConsumeIntegral<uint64_t>() & ((uint64_t{1} << 52) - 1);
    magnitude = __builtin_bit_cast(double, exponent << 52 | fraction);
    break;
  }
  default: {
    magnitude = ldexp(1.0, p.ConsumeIntegralInRange<int>(62, 64));
    int steps = p.ConsumeIntegralInRange<int>(-4, 4);
    for (; steps < 0; ++steps)
      magnitude = nextafter(magnitude, 0.0);
    for (; steps > 0; --steps)
      magnitude = nextafter(magnitude, INFINITY);
    break;
  }
  }
  double x = p.ConsumeBool() ? -magnitude : magnitude;
  prop::explain("x = %a", x);
  return x;
}

// add, mul, and, or, xor: each commutes, associates and has an identity.
struct Monoid {
  const char *name;
  Binary op;
  long identity;
};
constexpr Monoid monoids[] = {{"add", idris_rt_big_add, 0},
                              {"mul", idris_rt_big_mul, 1},
                              {"and", idris_rt_big_and, -1},
                              {"or", idris_rt_big_or, 0},
                              {"xor", idris_rt_big_xor, 0}};
// mul over add, and over or: outer(a, inner(b, c)) = inner(outer(a, b), outer(a, c)).
struct Distribution {
  const char *name;
  Binary outer, inner;
};
constexpr Distribution distributions[] = {{"mul over add", idris_rt_big_mul, idris_rt_big_add},
                                          {"and over or", idris_rt_big_and, idris_rt_big_or}};

// 9. The laws of the operations among themselves.
bool laws(const Operand &a, const Operand &b, const Operand &c, prop::Tally &tally) {
  bool ok = true;
  char what[64];
  for (const Monoid &m : monoids) {
    Result ab(m.op(a.word(), b.word())), ba(m.op(b.word(), a.word()));
    snprintf(what, sizeof what, "%s commutes", m.name);
    ok &= same(what, ab.word(), ba.word());
    Result abc(m.op(ab.word(), c.word())), bc(m.op(b.word(), c.word())), abc2(m.op(a.word(), bc.word()));
    snprintf(what, sizeof what, "%s associates", m.name);
    ok &= same(what, abc.word(), abc2.word());
    Operand identity(m.identity);
    Result kept(m.op(a.word(), identity.word()));
    snprintf(what, sizeof what, "%s by %ld", m.name, m.identity);
    ok &= same(what, kept.word(), a.word());
  }
  for (const Distribution &d : distributions) {
    Result bc(d.inner(b.word(), c.word())), left(d.outer(a.word(), bc.word()));
    Result ab(d.outer(a.word(), b.word())), ac(d.outer(a.word(), c.word())), right(d.inner(ab.word(), ac.word()));
    ok &= same(d.name, left.word(), right.word());
  }
  Operand zero(0L), one(1L), allOnes(-1L);
  Result negated(idris_rt_big_neg(a.word()));
  Result sum(idris_rt_big_add(a.word(), negated.word())), difference(idris_rt_big_sub(a.word(), a.word())),
      self(idris_rt_big_xor(a.word(), a.word())), twice(idris_rt_big_neg(negated.word()));
  ok &= same("a + neg a", sum.word(), zero.word());
  ok &= same("a - a", difference.word(), zero.word());
  ok &= same("a xor a", self.word(), zero.word());
  ok &= same("neg (neg a)", twice.word(), a.word());
  Result complement(idris_rt_big_xor(a.word(), allOnes.word())), less(idris_rt_big_sub(negated.word(), one.word()));
  ok &= same("a xor -1 and -a - 1", complement.word(), less.word());
  tally.classify(formsOf(a.word(), b.word(), c.word()));
  return ok;
}

// 10. Shifts compose and undo, for j, k >= 0: shr (shl a k) k = a;
// shl (shl a j) k = shl a (j + k); shl a k = a * shl 1 k; and
// shr a k = div a (shl 1 k).
bool undo(const Operand &a, unsigned long j, unsigned long k, prop::Tally &tally) {
  Operand jw(static_cast<long>(j)), kw(static_cast<long>(k)), jk(static_cast<long>(j + k)), one(1L);
  Result up(idris_rt_big_shl(a.word(), kw.word())), back(idris_rt_big_shr(up.word(), kw.word()));
  bool ok = same("shr (shl a k) k and a", back.word(), a.word());
  Result upJ(idris_rt_big_shl(a.word(), jw.word())), upJK(idris_rt_big_shl(upJ.word(), kw.word())),
      upSum(idris_rt_big_shl(a.word(), jk.word()));
  ok &= same("shl (shl a j) k and shl a (j + k)", upJK.word(), upSum.word());
  Result power(idris_rt_big_shl(one.word(), kw.word())), product(idris_rt_big_mul(a.word(), power.word()));
  ok &= same("shl a k and a * shl 1 k", up.word(), product.word());
  Result down(idris_rt_big_shr(a.word(), kw.word())), quotient(idris_rt_big_div(a.word(), power.word()));
  ok &= same("shr a k and div a (shl 1 k)", down.word(), quotient.word());
  tally.classify(formsOf(a.word(), up.word()));
  return ok;
}

// v wrapped to 63 bits of two's complement, the small range, where every
// integer has a small image: the families' values past the range fold onto
// its edges.
void wrapSmall(mpz_srcptr v, mpz_ptr out) {
  Z half;
  mpz_setbit(half, 62);
  mpz_add(out, v, half);
  mpz_fdiv_r_2exp(out, out, 63);
  mpz_sub(out, out, half);
}

// 11. Each entry gives what its large path gives, which takes any bigs.
bool paths(const Operand &a, const Operand &b, const Operand &amount, uint64_t word, prop::Tally &tally) {
  bool ok = true;
  auto relate = [&](const char *name, idris_rt_big entry, idris_rt_big large) {
    Result e(entry), l(large);
    ok &= same(name, e.word(), l.word());
  };
  for (const Arithmetic &op : arithmetic)
    relate(op.name, op.entry(a.word(), b.word()), op.large(a.word(), b.word()));
  for (const Bitwise &op : bitwise)
    relate(op.name, op.entry(a.word(), b.word()), op.large(a.word(), b.word()));
  definedShifts(a.value(), amount.value(), [&](const Shift &op, mpz_srcptr) {
    relate(op.name, op.entry(a.word(), amount.word()), op.large(a.word(), amount.word()));
  });
  for (const Single &op : singles)
    relate(op.name, op.entry(a.word()), op.large(a.word()));
  int entry = idris_rt_big_cmp(a.word(), b.word()), large = rt::big::cmpLarge(a.word(), b.word());
  if (signOf(entry) != signOf(large)) {
    prop::explain("cmp gives %d, its large path %d", entry, large);
    ok = false;
  }
  relate("from_int_u", idris_rt_big_from_int_u(word), rt::big::fromUnsignedLarge(word));
  relate("from_int_s", idris_rt_big_from_int_s(static_cast<int64_t>(word)),
         rt::big::largeOfInt64(static_cast<int64_t>(word)));
  // The operands are small, so the class is where a sum and a product go:
  // whether the entry's word operation kept them or overflowed.
  Result sum(idris_rt_big_add(a.word(), b.word())), product(idris_rt_big_mul(a.word(), b.word()));
  tally.classify(formsOf(sum.word(), product.word()));
  return ok;
}

// The edge values: around the small range's bounds, -2^62 and 2^62 - 1;
// +-2^61, past which a sum of small values leaves it; the least values;
// and the machine words' bounds, +-2^63 and 2^64. Each is
// sign * 2^exponent + adjust.
struct Edge {
  long sign;
  unsigned long exponent;
  long adjust;
};
constexpr Edge edges[] = {{-1, 62, -1}, {-1, 62, 0}, {-1, 62, 1}, {-1, 61, 0}, {-1, 1, 0}, {-1, 0, 0},
                          {0, 0, 0},    {1, 0, 0},   {1, 1, 0},   {1, 61, 0},  {1, 62, -2}, {1, 62, -1},
                          {1, 62, 0},   {1, 63, 0},  {-1, 63, 0}, {1, 64, 0}};
constexpr uint64_t edgeCount = sizeof edges / sizeof edges[0];
void edgeValue(uint64_t index, mpz_ptr out) {
  const Edge &e = edges[index];
  bigmodel::nearPower(out, e.sign, e.exponent, e.adjust);
  explainValues("edge %#Zx", static_cast<mpz_srcptr>(out));
}
// The amounts the box shifts every edge by: past two limbs either way.
constexpr long boxAmount = 130;

// The references a word holds of its cell; a small word is no object.
uint32_t referencesOf(idris_rt_big b) {
  if ((b & 1) != 0)
    return 0;
  idris_rt_header header;
  memcpy(&header, reinterpret_cast<const void *>(b), sizeof header);
  return header.count;
}

// A counted operand: a constant negated twice, a new cell of the same value
// when it is large.
class Counted {
public:
  explicit Counted(const Operand &c) {
    idris_rt_big once = idris_rt_big_neg(c.word());
    word_ = idris_rt_big_neg(once);
    idris_rt_big_release(once);
  }
  ~Counted() { idris_rt_big_release(word_); }
  Counted(const Counted &) = delete;
  Counted &operator=(const Counted &) = delete;
  idris_rt_big word() const { return word_; }

private:
  idris_rt_big word_;
};

// The word a call gives when its result is no big: the small 0, which owns
// nothing, so that every call is checked as one that returns a big.
constexpr idris_rt_big nothing = 1;

// One call, which borrows its operands a and b and returns one owned
// result: each operand keeps its references, but for the one more the
// result is when it is that operand's cell; once the result is released,
// the live cells are as before the call, and so are the operands'
// references.
template <typename Call> bool borrows(const char *name, idris_rt_big a, idris_rt_big b, Call call) {
  uint32_t ra = referencesOf(a), rb = referencesOf(b);
  uint64_t live = idris_rt_live_cells();
  idris_rt_big r = call();
  bool shaped = bigmodel::canonical(r);
  uint32_t ga = referencesOf(a), gb = referencesOf(b);
  bool kept = ga == ra + (r == a && (a & 1) == 0) && gb == rb + (r == b && (b & 1) == 0);
  idris_rt_big_release(r);
  bool freed = idris_rt_live_cells() == live;
  bool restored = referencesOf(a) == ra && referencesOf(b) == rb;
  if (!kept || !freed || !restored)
    prop::explain("%s: operands' references %u and %u became %u and %u, then %u and %u; live cells %llu, then %llu",
                  name, ra, rb, ga, gb, referencesOf(a), referencesOf(b), static_cast<unsigned long long>(live),
                  static_cast<unsigned long long>(idris_rt_live_cells()));
  return shaped && kept && freed && restored;
}

// 14. Every operation on counted operands.
bool ownership(const Operand &ca, const Operand &cb, const Operand &cAmount, prop::Tally &tally) {
  bool ok = true;
  Z dv, nv;
  divisorOf(cb.value(), dv);
  mpz_abs(nv, ca.value());
  mpz_add_ui(nv, nv, mpz_sgn(nv) == 0);
  Operand cd(dv), cn(nv);
  Counted a(ca), b(cb), amount(cAmount), d(cd), n(cn);
  for (const Arithmetic &op : arithmetic)
    ok &= borrows(op.name, a.word(), b.word(), [&] { return op.entry(a.word(), b.word()); });
  for (const Bitwise &op : bitwise)
    ok &= borrows(op.name, a.word(), b.word(), [&] { return op.entry(a.word(), b.word()); });
  definedShifts(ca.value(), cAmount.value(), [&](const Shift &op, mpz_srcptr) {
    ok &= borrows(op.name, a.word(), amount.word(), [&] { return op.entry(a.word(), amount.word()); });
  });
  for (const Single &op : singles)
    ok &= borrows(op.name, a.word(), a.word(), [&] { return op.entry(a.word()); });
  ok &= borrows("div", a.word(), d.word(), [&] { return idris_rt_big_div(a.word(), d.word()); });
  ok &= borrows("mod", a.word(), d.word(), [&] { return idris_rt_big_mod(a.word(), d.word()); });
  ok &= borrows("pred", n.word(), n.word(), [&] { return idris_rt_big_pred(n.word()); });
  ok &= borrows("cmp", a.word(), b.word(), [&] {
    (void)idris_rt_big_cmp(a.word(), b.word());
    return nothing;
  });
  ok &= borrows("to_int", a.word(), a.word(), [&] {
    (void)idris_rt_big_to_int(a.word());
    return nothing;
  });
  double x = idris_rt_big_to_double(a.word());
  ok &= borrows("to_double", a.word(), a.word(), [&] {
    (void)idris_rt_big_to_double(a.word());
    return nothing;
  });
  uint64_t u = low64(ca.value());
  ok &= borrows("from_int_s", nothing, nothing, [&] { return idris_rt_big_from_int_s(static_cast<int64_t>(u)); });
  ok &= borrows("from_int_u", nothing, nothing, [&] { return idris_rt_big_from_int_u(u); });
  ok &= borrows("from_double", nothing, nothing, [&] { return idris_rt_big_from_double(x); });
  tally.classify(formsOf(a.word(), b.word()));
  return ok;
}

} // namespace

int main(int argc, char **argv) {
  idris_rt_gmp_init();
  prop::Run run(argc, argv);

  run.property("add, sub, mul: the integer GMP computes", [](FuzzedDataProvider &p, prop::Tally &tally) {
    uint64_t mask = prop::swarm(p, bigmodel::families);
    Z av, bv;
    drawBig(p, mask, av, "a");
    drawBig(p, mask, bv, "b");
    Operand a(av), b(bv);
    return sums(a, b, tally);
  });

  run.property("div, mod: Euclidean: a = q*b + r and 0 <= r < |b|", [](FuzzedDataProvider &p, prop::Tally &tally) {
    uint64_t mask = prop::swarm(p, bigmodel::families);
    Z av, bv;
    drawBig(p, mask, av, "a");
    drawBig(p, mask, bv, "b");
    Operand a(av), b(bv);
    return division(a, b, tally);
  });

  run.property("and, or, xor: two's complement, bit by bit", [](FuzzedDataProvider &p, prop::Tally &tally) {
    uint64_t mask = prop::swarm(p, bigmodel::families);
    Z av, bv;
    drawBig(p, mask, av, "a");
    drawBig(p, mask, bv, "b");
    Operand a(av), b(bv);
    return bits(a, b, tally);
  });

  run.property("shl, shr: a * 2^k and floor(a / 2^k), the other way for k < 0",
               [](FuzzedDataProvider &p, prop::Tally &tally) {
                 uint64_t mask = prop::swarm(p, bigmodel::families);
                 Z av, kv;
                 drawBig(p, mask, av, "a");
                 unsigned family = prop::pick(p, prop::swarm(p, shiftFamilies));
                 drawShift(p, family, kv);
                 Operand a(av), amount(kv);
                 tally.classify(shiftNames[family]);
                 return shiftsBy(a, amount);
               });

  run.property("neg, cmp, nat_from_big, pred", [](FuzzedDataProvider &p, prop::Tally &tally) {
    uint64_t mask = prop::swarm(p, bigmodel::families);
    Z av, bv;
    drawBig(p, mask, av, "a");
    drawBig(p, mask, bv, "b");
    Operand a(av), b(bv);
    return order(a, b, tally);
  });

  run.property("from_int_s, from_int_u, to_int: exact, and to_int modulo 2^64",
               [](FuzzedDataProvider &p, prop::Tally &tally) {
                 Z av;
                 drawBig(p, prop::swarm(p, bigmodel::families), av, "a");
                 Operand a(av);
                 return machine(a, tally);
               });

  run.property("to_double: nearest, ties to even, infinity past the largest",
               [](FuzzedDataProvider &p, prop::Tally &tally) {
                 Z cv;
                 unsigned long s = widen(p, prop::pick(p, prop::swarm(p, wideFamilies)), cv);
                 explainValues("a = %#Zx * 2^%lu", static_cast<mpz_srcptr>(cv), s);
                 Operand c(cv), shift(static_cast<long>(s));
                 Result a(idris_rt_big_shl(c.word(), shift.word()));
                 bool ok = bigmodel::canonical(a.word());
                 ok &= nearest(a.word(), tally);
                 return ok;
               });

  run.property("from_double: truncated toward zero", [](FuzzedDataProvider &p, prop::Tally &tally) {
    return truncated(drawDouble(p, prop::pick(p, prop::swarm(p, doubleFamilies))), tally);
  });

  run.property("laws: commutative, associative, distributive, identities, inverses",
               [](FuzzedDataProvider &p, prop::Tally &tally) {
                 uint64_t mask = prop::swarm(p, bigmodel::families);
                 Z av, bv, cv;
                 drawBig(p, mask, av, "a");
                 drawBig(p, mask, bv, "b");
                 drawBig(p, mask, cv, "c");
                 Operand a(av), b(bv), c(cv);
                 return laws(a, b, c, tally);
               });

  run.property("laws: shifts compose and undo", [](FuzzedDataProvider &p, prop::Tally &tally) {
    Z av, jv, kv;
    drawBig(p, prop::swarm(p, bigmodel::families), av, "a");
    uint64_t mask = prop::swarm(p, boundedShiftFamilies);
    drawShift(p, prop::pick(p, mask), jv);
    drawShift(p, prop::pick(p, mask), kv);
    mpz_abs(jv, jv);
    mpz_abs(kv, kv);
    Operand a(av);
    return undo(a, mpz_get_ui(jv), mpz_get_ui(kv), tally);
  });

  run.property("small path = large path on small operands", [](FuzzedDataProvider &p, prop::Tally &tally) {
    uint64_t mask = prop::swarm(p, bigmodel::families);
    Z drawn, av, bv, kv, wv;
    drawBig(p, mask, drawn, "drawn a");
    wrapSmall(drawn, av);
    drawBig(p, mask, drawn, "drawn b");
    wrapSmall(drawn, bv);
    drawShift(p, prop::pick(p, prop::swarm(p, shiftFamilies)), drawn);
    wrapSmall(drawn, kv);
    drawBig(p, mask, wv, "word");
    Operand a(av), b(bv), amount(kv);
    return paths(a, b, amount, low64(wv), tally);
  });

  run.box("box: every pair of edge values, every operation", edgeCount * edgeCount, [](uint64_t input) {
    Z av, bv;
    edgeValue(input / edgeCount, av);
    edgeValue(input % edgeCount, bv);
    Operand a(av), b(bv);
    prop::Tally unused;
    // Every property runs, each explaining what fails.
    bool ok = sums(a, b, unused);
    ok &= division(a, b, unused);
    ok &= bits(a, b, unused);
    ok &= shiftsBy(a, b);
    ok &= order(a, b, unused);
    ok &= machine(a, unused);
    ok &= paths(a, b, b, low64(a.value()), unused);
    return ok;
  });

  run.box("box: every edge value shifted by every amount in [-130, 130]", edgeCount * (2 * boxAmount + 1),
          [](uint64_t input) {
            Z av;
            edgeValue(input / (2 * boxAmount + 1), av);
            long k = static_cast<long>(input % (2 * boxAmount + 1)) - boxAmount;
            prop::explain("amount %ld", k);
            Operand a(av), amount(k);
            return shiftsBy(a, amount);
          });

  run.property("every operation borrows its operands and returns one owned result",
               [](FuzzedDataProvider &p, prop::Tally &tally) {
                 uint64_t mask = prop::swarm(p, bigmodel::families);
                 Z av, bv, kv;
                 drawBig(p, mask, av, "a");
                 drawBig(p, mask, bv, "b");
                 drawShift(p, prop::pick(p, prop::swarm(p, shiftFamilies)), kv);
                 Operand a(av), b(bv), amount(kv);
                 uint64_t live = idris_rt_live_cells();
                 bool ok = ownership(a, b, amount, tally);
                 if (idris_rt_live_cells() != live) {
                   prop::explain("live cells %llu before the operands were counted, %llu after",
                                 static_cast<unsigned long long>(live),
                                 static_cast<unsigned long long>(idris_rt_live_cells()));
                   ok = false;
                 }
                 return ok;
               });

  return run.finish();
}
