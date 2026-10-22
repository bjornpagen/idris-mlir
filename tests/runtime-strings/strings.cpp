// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The runtime's string operations held to a model (idris_rt.h's strings):
// a string is its scalars, and its bytes are their UTF-8
// (utf8model::encode). Every result is the model's, canonical (its lengths
// are its bytes' and its scalars' counts), a string of its own and never an
// operand, every operand only borrowed, and every empty result the one
// empty string. An operand is a persistent constant, laid out as idr-lower
// writes a string into static data, or a counted string.
#include "idris_rt.h"
#include "prop.h"
#include "runtime.h"
#include "utf8model.h"

#include <stddef.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>

namespace {

using utf8model::table37;

// The most scalars an operand has: several of every family in one, and two
// operands' draws within a case's bytes (a scalar draws at most 5: its
// family, its row and a code point of up to 3, so two operands at most 640
// of prop::caseBytes).
constexpr size_t operandLimit = 64;
// The longest result, the append of two operands.
constexpr size_t resultLimit = 2 * operandLimit;
// UTF-8 writes a scalar in at most 4 bytes.
constexpr size_t scalarBytes = 4;

// A string as the model has it: its scalars, in order.
struct Model {
  uint32_t at[resultLimit];
  size_t length = 0;
  void push(uint32_t scalar) { at[length++] = scalar; }
};

// The model's bytes: the UTF-8 of its scalars.
struct Encoded {
  unsigned char bytes[resultLimit * scalarBytes];
  size_t length = 0;
  explicit Encoded(const Model &m) {
    for (size_t i = 0; i < m.length; ++i)
      length += utf8model::encode(m.at[i], bytes + length);
  }
};

// The operations, as the runtime states them of scalars.
Model tailOf(const Model &s) {
  Model r;
  for (size_t i = 1; i < s.length; ++i)
    r.push(s.at[i]);
  return r;
}
Model appendOf(const Model &a, const Model &b) {
  Model r;
  for (size_t i = 0; i < a.length; ++i)
    r.push(a.at[i]);
  for (size_t i = 0; i < b.length; ++i)
    r.push(b.at[i]);
  return r;
}
Model fromCharOf(uint32_t c) {
  Model r;
  r.push(c);
  return r;
}
Model consOf(uint32_t c, const Model &s) { return appendOf(fromCharOf(c), s); }
Model reverseOf(const Model &s) {
  Model r;
  for (size_t i = s.length; i > 0; --i)
    r.push(s.at[i - 1]);
  return r;
}
int64_t clamp(int64_t v, int64_t low, int64_t high) { return v < low ? low : v > high ? high : v; }
// The Prelude's substr: the scalars from `start`, at most `length` of them.
// Clamped, the rule has no exception: the first index is start clamped to
// [0, n] and the count length clamped to [0, n - first], so a negative
// counts as 0, a start past the end gives no scalar and a length past the
// end gives those left.
Model substrOf(const Model &s, int64_t start, int64_t length) {
  auto n = static_cast<int64_t>(s.length);
  int64_t first = clamp(start, 0, n);
  int64_t count = clamp(length, 0, n - first);
  Model r;
  for (int64_t i = first; i < first + count; ++i)
    r.push(s.at[i]);
  return r;
}
// The order of the scalars, a proper prefix first: -1, 0 or 1.
int compareOf(const Model &a, const Model &b) {
  for (size_t i = 0; i < a.length && i < b.length; ++i)
    if (a.at[i] != b.at[i])
      return a.at[i] < b.at[i] ? -1 : 1;
  return a.length < b.length ? -1 : a.length > b.length ? 1 : 0;
}

// The faults each check must notice, planted where it reads the runtime
// (prop.h): the mistakes of an operation that takes bytes for scalars, or
// that misses an end of the string, a reference or the one empty string.
constexpr prop::Mutant lengthOfBytes{"counts a string's length in bytes"};
constexpr prop::Mutant tailOfAByte{"has tail drop one byte, not one scalar"};
constexpr prop::Mutant reverseOfBytes{"reverses a string's bytes, not its scalars"};
constexpr prop::Mutant startFromTheEnd{"reads a negative substr start as counted from the end"};
constexpr prop::Mutant signedBytes{"orders strings by their bytes read as signed chars"};
constexpr prop::Mutant givesOperandBack{"gives an operand back as its result"};
constexpr prop::Mutant pastTheEndEmpty{"gives the empty string for a substr whose length runs past the end"};
constexpr prop::Mutant keepsReference{"keeps a reference to a counted operand"};
constexpr prop::Mutant secondEmpty{"makes an empty string of its own for substr of no scalars"};

// A string's scalars, for an explanation.
struct Shown {
  char text[resultLimit * 9 + 1];
  explicit Shown(const Model &m) {
    size_t at = 0;
    text[0] = '\0';
    for (size_t i = 0; i < m.length; ++i)
      at += static_cast<size_t>(snprintf(text + at, sizeof text - at, i == 0 ? "U+%04X" : " U+%04X", m.at[i]));
  }
};

// A persistent string as idris_rt.h lays out a string and idr-lower writes
// one into static data: the header with count 0 and a string's info, its
// lengths, then its bytes, word-aligned as idris_rt_str's words make it.
struct Constant {
  idris_rt_str string;
  unsigned char bytes[operandLimit * scalarBytes];
};
static_assert(offsetof(Constant, bytes) == sizeof(idris_rt_str), "a string's bytes follow its lengths");

// How an operand reaches the runtime: the persistent constant itself, or a
// new string of its bytes from idris_rt_str_from_utf8. A case's class is
// the pair of its operands' forms, the first's `pairedWith` the second's.
struct Form {
  const idris_rt_str *(*make)(const Constant &);
  const char *pairedWith[2];
};
constexpr Form forms[] = {
    {[](const Constant &c) { return &c.string; }, {"persistent and persistent", "persistent and counted"}},
    {[](const Constant &c) {
       return idris_rt_str_from_utf8(reinterpret_cast<const char *>(c.bytes), c.string.bytes);
     },
     {"counted and persistent", "counted and counted"}},
};
constexpr unsigned formCount = sizeof forms / sizeof forms[0];

// An operand: its model, its form, and the string the runtime is handed,
// which it owns. Releasing a persistent string does nothing (idris_rt.h),
// so both forms are released alike.
struct Operand {
  Model model;
  const Form *form;
  Constant constant;
  const idris_rt_str *string;
  Operand(const Model &m, const Form &f) : model(m), form(&f) { make(); }
  Operand(FuzzedDataProvider &p, uint64_t mask);
  ~Operand() { idris_rt_dec_cell(const_cast<idris_rt_header *>(&string->header)); }
  Operand(const Operand &) = delete;
  Operand &operator=(const Operand &) = delete;

private:
  void make() {
    Encoded encoded(model);
    constant.string = {{0, idris_rt_info(0, 0, IDRIS_RT_KIND_STRING)}, encoded.length, model.length};
    memcpy(constant.bytes, encoded.bytes, encoded.length);
    string = form->make(constant);
  }
};

// A scalar of `length` bytes: a row of Table 3-7 of that length, whose rows
// the table lists by length, and one of its code points.
uint32_t scalarOfLength(FuzzedDataProvider &p, size_t length) {
  size_t first = 0;
  while (table37[first].length != length)
    ++first;
  size_t end = first;
  while (end < utf8model::rows && table37[end].length == length)
    ++end;
  const utf8model::Row &row = table37[p.ConsumeIntegralInRange<size_t>(first, end - 1)];
  return p.ConsumeIntegralInRange<uint32_t>(row.first, row.last);
}

// The scalar families, simplest first: the scalars UTF-8 writes in one,
// two, three and four bytes (Table 3-7's rows of that length, so three
// bytes leave out the surrogates, which no row holds), and the first or
// last scalar of a row, where the rows meet.
struct ScalarFamily {
  const char *name;
  uint32_t (*draw)(FuzzedDataProvider &);
};
constexpr ScalarFamily scalarFamilies[] = {
    {"ASCII", [](FuzzedDataProvider &p) { return scalarOfLength(p, 1); }},
    {"two bytes", [](FuzzedDataProvider &p) { return scalarOfLength(p, 2); }},
    {"three bytes", [](FuzzedDataProvider &p) { return scalarOfLength(p, 3); }},
    {"four bytes", [](FuzzedDataProvider &p) { return scalarOfLength(p, 4); }},
    {"a row's first or last",
     [](FuzzedDataProvider &p) {
       const utf8model::Row &row = table37[p.ConsumeIntegralInRange<size_t>(0, utf8model::rows - 1)];
       return p.ConsumeBool() ? row.last : row.first;
     }},
};
constexpr unsigned scalarFamilyCount = sizeof scalarFamilies / sizeof scalarFamilies[0];

uint32_t drawScalar(FuzzedDataProvider &p, uint64_t mask) {
  return scalarFamilies[prop::pick(p, mask)].draw(p);
}
Model drawModel(FuzzedDataProvider &p, uint64_t mask) {
  Model m;
  size_t length = p.ConsumeIntegralInRange<size_t>(0, operandLimit);
  while (m.length < length)
    m.push(drawScalar(p, mask));
  return m;
}
// Its model, then its form: members are made in order, so the draws are
// the same on every target.
Operand::Operand(FuzzedDataProvider &p, uint64_t mask)
    : model(drawModel(p, mask)), form(&forms[p.ConsumeIntegralInRange<unsigned>(0, formCount - 1)]) {
  make();
}

// substr's arguments: from [-3, n + 3], so each side of each end, or an
// int64 edge.
int64_t drawArgument(FuzzedDataProvider &p, size_t n) {
  constexpr int64_t edges[] = {INT64_MIN, INT64_MAX};
  return p.ConsumeBool() ? p.PickValueInArray(edges)
                         : p.ConsumeIntegralInRange<int64_t>(-3, static_cast<int64_t>(n) + 3);
}

// The box's alphabet: a scalar of each length.
constexpr uint32_t alphabet[] = {0x61, 0xE9, 0x20AC, 0x1F600};
constexpr unsigned letters = sizeof alphabet / sizeof alphabet[0];
// The box's starts and lengths, every one in [-2, 5]: each side of both
// ends of its strings of up to 3 scalars. A case draws at most as many
// (start, length) pairs as the box takes.
constexpr int64_t boxLow = -2;
constexpr int64_t boxHigh = 5;
constexpr size_t argumentLimit = (boxHigh - boxLow + 1) * (boxHigh - boxLow + 1);

// What the operations other than their string operands are called with:
// scalars for cons and from_char (a case's one, or the box's alphabet), and
// (start, length) pairs for substr.
struct Arguments {
  uint32_t scalars[letters];
  size_t scalarCount = 0;
  int64_t starts[argumentLimit];
  int64_t lengths[argumentLimit];
  size_t pairs = 0;
};

// A case: the scalar families swarmed, two operands of them in drawn
// forms, and the other arguments: one scalar, and substr's pairs for the
// first operand until the case's bytes run out (at least one).
struct Case {
  uint64_t mask;
  Operand a, b;
  Arguments arguments;
  Case(FuzzedDataProvider &p, prop::Tally &tally)
      : mask(prop::swarm(p, scalarFamilyCount)), a(p, mask), b(p, mask) {
    arguments.scalars[arguments.scalarCount++] = drawScalar(p, mask);
    do {
      arguments.starts[arguments.pairs] = drawArgument(p, a.model.length);
      arguments.lengths[arguments.pairs] = drawArgument(p, a.model.length);
      ++arguments.pairs;
    } while (p.remaining_bytes() > 0 && arguments.pairs < argumentLimit);
    tally.classify(a.form->pairedWith[b.form - forms]);
  }
};

// A result the model's: its bytes are the encoding of the model's scalars
// and its scalar count their number.
bool isTheModel(const char *operation, const idris_rt_str *r, const Model &m) {
  Encoded want(m);
  bool holds = r->bytes == want.length && memcmp(idris_rt_str_bytes(r), want.bytes, want.length) == 0 &&
               r->scalars == m.length;
  if (!holds) {
    prop::explain("%s: the model's %zu scalars are %s", operation, m.length, Shown(m).text);
    prop::explain("%s: the runtime's string has %llu bytes, %llu scalars", operation,
                  static_cast<unsigned long long>(r->bytes), static_cast<unsigned long long>(r->scalars));
  }
  return holds;
}

// What one call of an operation that returns a string is held to: its
// operands, which it borrows; and the model's result.
struct Expected {
  const char *name;
  const idris_rt_str *operands[2];
  size_t operandCount;
  Model model;
};

// The operands keep their counts through `call` and the live cells are as
// they were after it: it borrowed them and released what it made.
template <typename Call>
bool borrowed(const char *operation, const idris_rt_str *const *operands, size_t n, Call call) {
  uint32_t counts[2];
  for (size_t i = 0; i < n; ++i)
    counts[i] = operands[i]->header.count;
  uint64_t live = prop::held();
  call();
  bool holds = prop::held() == live;
  for (size_t i = 0; i < n; ++i) {
    uint32_t count = operands[i]->header.count;
    if (count != 0 && prop::planted(keepsReference))
      ++count;
    holds = holds && count == counts[i];
  }
  if (!holds)
    prop::explain("%s: an operand's count or the live cells changed", operation);
  return holds;
}

// The judges of a call: the model's result (properties 2 to 4); canonical
// and owned (6); borrowed operands (8); and all three (the box).
struct Models {
  template <typename Call> bool operator()(const Expected &e, Call call) const {
    const idris_rt_str *r = call();
    bool holds = isTheModel(e.name, r, e.model);
    idris_rt_dec_cell(const_cast<idris_rt_header *>(&r->header));
    return holds;
  }
};
// A result is a string of its own, never an operand, even where it reads
// as one (appending the empty string, reversing a string of one scalar): a
// result is fresh, so an operation that gave an operand back would share
// what its caller may hold exclusive. The persistent empty one (count 0)
// when it has no byte, else a new one (count 1).
struct Owns {
  template <typename Call> bool operator()(const Expected &e, Call call) const {
    const idris_rt_str *r = call();
    const idris_rt_str *seen = e.operandCount > 0 && prop::planted(givesOperandBack) ? e.operands[0] : r;
    bool fresh = true;
    for (size_t i = 0; i < e.operandCount; ++i)
      fresh = fresh && (seen != e.operands[i] || seen->bytes == 0);
    bool owned = fresh && seen->header.count == (seen->bytes == 0 ? 0u : 1u);
    bool holds = isTheModel(e.name, r, e.model) && owned;
    if (!owned)
      prop::explain("%s: a result of count %u%s, where idris_rt.h makes the persistent empty string or a new one",
                    e.name, seen->header.count, fresh ? "" : " that is an operand");
    idris_rt_dec_cell(const_cast<idris_rt_header *>(&r->header));
    return holds;
  }
};
struct Borrows {
  template <typename Call> bool operator()(const Expected &e, Call call) const {
    return borrowed(e.name, e.operands, e.operandCount, [&] { idris_rt_dec_cell(const_cast<idris_rt_header *>(&call()->header)); });
  }
};
struct Every {
  template <typename Call> bool operator()(const Expected &e, Call call) const {
    return Models{}(e, call) && Owns{}(e, call) && Borrows{}(e, call);
  }
};

// The operations that return a string, each called and judged. idr-lower
// checks a precondition before the call and crashes when it does not hold,
// so the tail of an empty string is never asked for.
template <typename Judge> bool tail(const Operand &s, Judge judge) {
  if (s.model.length == 0)
    return true;
  return judge(Expected{"tail", {s.string}, 1, tailOf(s.model)}, [&] {
    return prop::planted(tailOfAByte) ? idris_rt_str_from_bytes(idris_rt_str_bytes(s.string) + 1, s.string->bytes - 1)
                                      : idris_rt_str_tail(s.string);
  });
}
template <typename Judge> bool cons(uint32_t c, const Operand &s, Judge judge) {
  return judge(Expected{"cons", {s.string}, 1, consOf(c, s.model)},
               [&] { return idris_rt_str_cons(static_cast<int32_t>(c), s.string); });
}
template <typename Judge> bool fromChar(uint32_t c, Judge judge) {
  return judge(Expected{"from_char", {}, 0, fromCharOf(c)},
               [&] { return idris_rt_str_from_char(static_cast<int32_t>(c)); });
}
template <typename Judge> bool append(const Operand &a, const Operand &b, Judge judge) {
  return judge(Expected{"append", {a.string, b.string}, 2, appendOf(a.model, b.model)},
               [&] { return idris_rt_str_append(a.string, b.string); });
}
template <typename Judge> bool reverse(const Operand &s, Judge judge) {
  return judge(Expected{"reverse", {s.string}, 1, reverseOf(s.model)}, [&] {
    if (s.model.length > 0 && prop::planted(reverseOfBytes)) {
      char bytes[operandLimit * scalarBytes];
      for (uint64_t k = 0; k < s.string->bytes; ++k)
        bytes[k] = idris_rt_str_bytes(s.string)[s.string->bytes - 1 - k];
      return idris_rt_str_from_bytes(bytes, s.string->bytes);
    }
    return idris_rt_str_reverse(s.string);
  });
}
template <typename Judge> bool substr(const Operand &s, int64_t start, int64_t length, Judge judge) {
  auto n = static_cast<int64_t>(s.model.length);
  bool holds = judge(Expected{"substr", {s.string}, 1, substrOf(s.model, start, length)}, [&] {
    if (start < 0 && start > INT64_MIN && n > 0 && prop::planted(startFromTheEnd))
      return idris_rt_str_substr(s.string, n + start < 0 ? 0 : n + start, length);
    if (start >= 0 && start < n && length > n - start && prop::planted(pastTheEndEmpty))
      return idris_rt_str_substr(s.string, start, 0);
    return idris_rt_str_substr(s.string, start, length);
  });
  if (!holds)
    prop::explain("substr of %zu scalars from %lld, at most %lld", s.model.length, static_cast<long long>(start),
                  static_cast<long long>(length));
  return holds;
}

template <typename Judge> bool substrs(const Operand &s, const Arguments &args, Judge judge) {
  bool holds = true;
  for (size_t i = 0; i < args.pairs && holds; ++i)
    holds = substr(s, args.starts[i], args.lengths[i], judge);
  return holds;
}
template <typename Judge> bool tailConsFromCharAppend(const Operand &a, const Operand &b, const Arguments &args,
                                                      Judge judge) {
  bool holds = tail(a, judge) && tail(b, judge) && append(a, b, judge) && append(b, a, judge);
  for (size_t i = 0; i < args.scalarCount && holds; ++i)
    holds = cons(args.scalars[i], a, judge) && cons(args.scalars[i], b, judge) && fromChar(args.scalars[i], judge);
  return holds;
}
// Every operation that returns a string, on a case's operands and arguments.
template <typename Judge>
bool stringOperations(const Operand &a, const Operand &b, const Arguments &args, Judge judge) {
  return tailConsFromCharAppend(a, b, args, judge) && reverse(a, judge) && reverse(b, judge) &&
         substrs(a, args, judge);
}

// length, index at every index, and head of a nonempty string: the model's.
bool scalarsOf(const Operand &s) {
  int64_t length = idris_rt_str_length(s.string);
  if (prop::planted(lengthOfBytes))
    length = static_cast<int64_t>(s.string->bytes);
  bool holds = length == static_cast<int64_t>(s.model.length);
  for (size_t i = 0; i < s.model.length && holds; ++i)
    holds = static_cast<uint32_t>(idris_rt_str_index(s.string, static_cast<int64_t>(i))) == s.model.at[i];
  if (holds && s.model.length > 0)
    holds = static_cast<uint32_t>(idris_rt_str_head(s.string)) == s.model.at[0];
  if (!holds)
    prop::explain("length %lld, index or head differ from the model's %zu scalars %s",
                  static_cast<long long>(idris_rt_str_length(s.string)), s.model.length, Shown(s.model).text);
  return holds;
}

// cmp's sign is the model's order, both ways and of each operand with
// itself.
bool compares(const Operand &a, const Operand &b) {
  auto sign = [](int32_t c) { return c < 0 ? -1 : c > 0 ? 1 : 0; };
  const Operand *pairs[][2] = {{&a, &b}, {&b, &a}, {&a, &a}, {&b, &b}};
  // The mutant's order: the first byte that differs, read as a signed char,
  // else the shorter first.
  auto signedOrder = [](const idris_rt_str *x, const idris_rt_str *y) {
    for (uint64_t k = 0; k < x->bytes && k < y->bytes; ++k) {
      auto c = static_cast<signed char>(idris_rt_str_bytes(x)[k]);
      auto d = static_cast<signed char>(idris_rt_str_bytes(y)[k]);
      if (c != d)
        return c < d ? -1 : 1;
    }
    return x->bytes < y->bytes ? -1 : x->bytes > y->bytes ? 1 : 0;
  };
  for (const auto &pair : pairs) {
    int got = sign(idris_rt_str_cmp(pair[0]->string, pair[1]->string));
    if (prop::planted(signedBytes))
      got = signedOrder(pair[0]->string, pair[1]->string);
    int want = compareOf(pair[0]->model, pair[1]->model);
    if (got != want) {
      prop::explain("cmp gives %d where the order of the scalars is %d:", got, want);
      prop::explain("  %s", Shown(pair[0]->model).text);
      prop::explain("  %s", Shown(pair[1]->model).text);
      return false;
    }
  }
  return true;
}

// The operations that return no string borrow their operands too.
bool scalarOperationsBorrow(const Operand &a, const Operand &b) {
  const idris_rt_str *both[] = {a.string, b.string};
  bool holds = borrowed("length", both, 1, [&] { idris_rt_str_length(a.string); }) &&
               borrowed("cmp", both, 2, [&] { idris_rt_str_cmp(a.string, b.string); });
  for (size_t i = 0; i < a.model.length && holds; ++i)
    holds = borrowed("index", both, 1, [&] { idris_rt_str_index(a.string, static_cast<int64_t>(i)); });
  if (holds && a.model.length > 0)
    holds = borrowed("head", both, 1, [&] { idris_rt_str_head(a.string); });
  return holds;
}

// The one empty string: every operation that gives a string of no bytes,
// and does not give an operand back, gives the same string, persistent
// (count 0), and allocates nothing for it. On an operand: the constructors
// given no bytes of it (from_utf8, from_bytes, str_alloc, a byte array's
// get_string at either end), and the operations whose result is empty
// (substr from the end and of no scalars, tail of one scalar, drop_bytes
// to the end of a string that is not empty).
bool emptiesAreOne(const Operand &s) {
  auto bytes = static_cast<int64_t>(s.string->bytes);
  auto length = static_cast<int64_t>(s.model.length);
  auto *buffer = static_cast<idris_rt_array *>(
      idris_rt_array_new_unwritten(static_cast<uint64_t>(bytes), idris_rt_info(1, 0, IDRIS_RT_KIND_ARRAY)));
  memcpy(idris_rt_array_bytes(buffer), idris_rt_str_bytes(s.string), s.string->bytes);
  uint64_t live = prop::held();
  struct Made {
    const char *operation;
    const idris_rt_str *string;
  };
  Made made[11];
  size_t count = 0;
  auto add = [&](const char *operation, const idris_rt_str *string) { made[count++] = {operation, string}; };
  add("from_utf8 of no bytes", idris_rt_str_from_utf8(idris_rt_str_bytes(s.string), 0));
  add("from_bytes of no bytes", idris_rt_str_from_bytes(idris_rt_str_bytes(s.string), 0));
  add("str_alloc of no bytes", idris_rt_str_alloc(0, 0));
  add("buffer_get_string of no bytes at 0", idris_rt_io_buffer_get_string(buffer, 0, 0));
  add("buffer_get_string of no bytes at the end", idris_rt_io_buffer_get_string(buffer, bytes, 0));
  add("substr from the end", idris_rt_str_substr(s.string, length, 1));
  add("substr past the end", idris_rt_str_substr(s.string, length + 1, length));
  add("substr of no scalars", idris_rt_str_substr(s.string, 0, 0));
  if (length == 1)
    add("tail of one scalar", idris_rt_str_tail(s.string));
  // drop_bytes from 0 gives the string itself back, so an empty one is not
  // made.
  if (bytes > 0) {
    add("drop_bytes to the end", idris_rt_str_drop_bytes(s.string, bytes));
    add("drop_bytes past the end", idris_rt_str_drop_bytes(s.string, INT64_MAX));
  }
  bool holds = prop::held() == live;
  if (!holds)
    prop::explain("an empty string allocated a cell");
  const idris_rt_str *one = made[0].string;
  holds = holds && one->header.count == 0 && one->bytes == 0 && one->scalars == 0 &&
          one->header.info == idris_rt_info(0, 0, IDRIS_RT_KIND_STRING);
  for (size_t i = 0; i < count; ++i) {
    const Made &m = made[i];
    bool other = m.string != one || (strcmp(m.operation, "substr of no scalars") == 0 && prop::planted(secondEmpty));
    if (holds && other) {
      prop::explain("%s: a string of %llu bytes and count %u, not the one empty string", m.operation,
                    static_cast<unsigned long long>(m.string->bytes), m.string->header.count);
      holds = false;
    }
    idris_rt_dec_cell(const_cast<idris_rt_header *>(&m.string->header));
  }
  idris_rt_dec_cell(&buffer->header);
  return holds;
}

// Every string of at most 3 of them: 1 + 4 + 16 + 64.
constexpr uint64_t boxStrings = 1 + letters + letters * letters + letters * letters * letters;
// The string numbered `index` in bijective base 4: 0 is the empty string,
// then every string of one letter, then of two, then of three.
Model boxString(uint64_t index) {
  Model m;
  for (; index > 0; index = (index - 1) / letters)
    m.push(alphabet[(index - 1) % letters]);
  return m;
}

} // namespace

static int properties(int argc, char **argv) {
  prop::Run run(argc, argv);

  run.property("length, index, head: the model's", lengthOfBytes, [](FuzzedDataProvider &p, prop::Tally &tally) {
    Case k(p, tally);
    return scalarsOf(k.a) && scalarsOf(k.b);
  });

  run.property("tail, cons, from_char, append: the model's", tailOfAByte,
               [](FuzzedDataProvider &p, prop::Tally &tally) {
    Case k(p, tally);
    return tailConsFromCharAppend(k.a, k.b, k.arguments, Models{});
  });

  run.property("reverse: the model's", reverseOfBytes, [](FuzzedDataProvider &p, prop::Tally &tally) {
    Case k(p, tally);
    return reverse(k.a, Models{}) && reverse(k.b, Models{});
  });

  run.property("substr: the model's, negative and past-the-end arguments included", startFromTheEnd,
               [](FuzzedDataProvider &p, prop::Tally &tally) {
                 Case k(p, tally);
                 return substrs(k.a, k.arguments, Models{});
               });

  run.property("cmp: the order of the scalars", signedBytes, [](FuzzedDataProvider &p, prop::Tally &tally) {
    Case k(p, tally);
    return compares(k.a, k.b);
  });

  run.property("results: canonical, the empty one persistent, every other a new string, never an operand",
               givesOperandBack,
               [](FuzzedDataProvider &p, prop::Tally &tally) {
                 Case k(p, tally);
                 return stringOperations(k.a, k.b, k.arguments, Owns{});
               });

  // Each input: a string and its form, then another and its form.
  constexpr uint64_t operands = boxStrings * formCount;
  run.box("box: every string of at most 3 scalars over a, U+00E9, U+20AC, U+1F600, every operation",
          operands * operands, pastTheEndEmpty, [](uint64_t index) {
            uint64_t first = index / operands;
            uint64_t second = index % operands;
            Operand a(boxString(first / formCount), forms[first % formCount]);
            Operand b(boxString(second / formCount), forms[second % formCount]);
            Arguments args;
            for (uint32_t c : alphabet)
              args.scalars[args.scalarCount++] = c;
            for (int64_t start = boxLow; start <= boxHigh; ++start)
              for (int64_t length = boxLow; length <= boxHigh; ++length) {
                args.starts[args.pairs] = start;
                args.lengths[args.pairs++] = length;
              }
            return scalarsOf(a) && scalarsOf(b) && compares(a, b) && stringOperations(a, b, args, Every{}) &&
                   scalarOperationsBorrow(a, b);
          });

  run.property("every operation borrows its operands and returns one owned result", keepsReference,
               [](FuzzedDataProvider &p, prop::Tally &tally) {
                 Case k(p, tally);
                 return stringOperations(k.a, k.b, k.arguments, Borrows{}) && scalarOperationsBorrow(k.a, k.b);
               });

  run.property("the empty string: every operation that makes one gives the one persistent empty string",
               secondEmpty,
               [](FuzzedDataProvider &p, prop::Tally &tally) {
                 Case k(p, tally);
                 return emptiesAreOne(k.a) && emptiesAreOne(k.b);
               });

  return run.finish();
}

int main(int argc, char **argv) { return prop::onRuntime(argc, argv, "strings", properties); }
