// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// Bytes as a string, held to the Unicode Standard (idris_rt.h:
// idris_rt_str_from_bytes, idris_rt_str_from_utf8, idris_rt_utf8_count).
// The model (utf8model.h) is first checked against the Standard's own
// example, then judges the runtime: random byte strings, every string of
// two bytes, every pair of bytes at one of simdutf's 64-byte blocks'
// boundaries, and every row of Table 3-7 cut at such a boundary.
#include "idris_rt.h"
#include "prop.h"
#include "utf8model.h"

#include <stddef.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>

namespace {

using utf8model::table37;

// simdutf validates 64 bytes at a time (simd8x64,
// third_party/simdutf/src/generic/utf8_validation/utf8_lookup4_algorithm.h)
// and carries an unfinished sequence from one block to the next.
constexpr size_t block = 64;
// The longest random input: five blocks, so its runs cross four boundaries.
constexpr size_t longest = 5 * block;
// An input byte decodes to at most three: a U+FFFD (EF BF BD) of one byte,
// or a scalar's own bytes.
constexpr size_t decodedRoom = 3 * longest;
// The run of `x` boxes 4 and 5 put bytes into: three blocks, so the bytes
// sit at the first boundary with a whole block on each side.
constexpr size_t runLength = 3 * block;

// The n bytes at p as hex pairs, for an explanation.
struct Hex {
  char text[3 * longest + 1];
  Hex(const void *p, size_t n) {
    const auto *bytes = static_cast<const unsigned char *>(p);
    size_t at = 0;
    text[0] = '\0';
    for (size_t i = 0; i < n && at + 4 <= sizeof text; ++i)
      at += static_cast<size_t>(snprintf(text + at, sizeof text - at, i == 0 ? "%02X" : " %02X", bytes[i]));
  }
};

// The model's string of the n bytes at p: the encodings of the scalars
// utf8model::decode reads, and their count.
struct Decoded {
  unsigned char bytes[decodedRoom];
  size_t length = 0;
  size_t scalars = 0;
  Decoded(const unsigned char *p, size_t n) {
    uint32_t scalar[longest];
    scalars = utf8model::decode(p, n, scalar);
    for (size_t i = 0; i < scalars; ++i)
      length += utf8model::encode(scalar[i], bytes + length);
  }
  // The input was well-formed: decoding gave its own bytes back.
  bool same(const unsigned char *p, size_t n) const {
    return length == n && memcmp(bytes, p, n) == 0;
  }
};

// idris_rt_str_from_bytes of the n bytes at p is the model's string: its
// bytes and its scalar count; idris_rt_utf8_count counts its bytes the same;
// and from_bytes of its bytes, which are well-formed, gives them back.
bool fromBytesIsTheModel(const unsigned char *p, size_t n) {
  Decoded want(p, n);
  const idris_rt_str *got = idris_rt_str_from_bytes(reinterpret_cast<const char *>(p), n);
  const char *bytes = idris_rt_str_bytes(got);
  const idris_rt_str *again = idris_rt_str_from_bytes(bytes, got->bytes);
  bool same = got->bytes == want.length && memcmp(bytes, want.bytes, want.length) == 0;
  bool counted = got->scalars == want.scalars && idris_rt_utf8_count(bytes, got->bytes) == want.scalars;
  bool stable = again->bytes == got->bytes && again->scalars == got->scalars &&
                memcmp(idris_rt_str_bytes(again), bytes, got->bytes) == 0;
  if (!(same && counted && stable)) {
    size_t differs = 0;
    while (differs < got->bytes && differs < want.length &&
           static_cast<unsigned char>(bytes[differs]) == want.bytes[differs])
      ++differs;
    prop::explain("input of %zu bytes: %s", n, Hex(p, n).text);
    prop::explain("from_bytes's bytes and the model's first differ at byte %zu", differs);
    prop::explain("the model: %zu scalars, %s", want.scalars, Hex(want.bytes, want.length).text);
    prop::explain("from_bytes: %llu scalars, %s", static_cast<unsigned long long>(got->scalars),
                  Hex(bytes, got->bytes).text);
    prop::explain("utf8_count of its bytes: %zu", idris_rt_utf8_count(bytes, got->bytes));
    prop::explain("from_bytes again: %llu scalars, %llu bytes%s",
                  static_cast<unsigned long long>(again->scalars),
                  static_cast<unsigned long long>(again->bytes), stable ? "" : ", not the same");
  }
  idris_rt_str_release(again);
  idris_rt_str_release(got);
  return same && counted && stable;
}

// A scalar of `length` bytes: a row of Table 3-7 of that length, whose rows
// the table lists by length, and one of its code points. Table 3-7 has no
// surrogate, so neither does a scalar drawn from it.
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

// The bytes `in` says yes to, listed.
struct Bytes {
  unsigned char at[256] = {};
  size_t count = 0;
};
template <bool (*In)(unsigned char)> constexpr Bytes bytesWhere() {
  Bytes set;
  for (unsigned byte = 0; byte < 256; ++byte)
    if (In(static_cast<unsigned char>(byte)))
      set.at[set.count++] = static_cast<unsigned char>(byte);
  return set;
}
// Where Table 3-7 puts a byte: first in a row of two or more bytes; in a
// later place of some row; in no place of any row.
constexpr bool leads(unsigned char byte) {
  for (const utf8model::Row &row : table37)
    if (row.length > 1 && row.bytes[0].holds(byte))
      return true;
  return false;
}
constexpr bool continues(unsigned char byte) {
  for (const utf8model::Row &row : table37)
    for (size_t k = 1; k < row.length; ++k)
      if (row.bytes[k].holds(byte))
        return true;
  return false;
}
constexpr bool heldNowhere(unsigned char byte) {
  for (const utf8model::Row &row : table37)
    for (size_t k = 0; k < row.length; ++k)
      if (row.bytes[k].holds(byte))
        return false;
  return true;
}
constexpr Bytes leadBytes = bytesWhere<leads>();
constexpr Bytes continuationBytes = bytesWhere<continues>();
constexpr Bytes strayBytes = bytesWhere<heldNowhere>();

unsigned char oneOf(FuzzedDataProvider &p, const Bytes &set) {
  return set.at[p.ConsumeIntegralInRange<size_t>(0, set.count - 1)];
}

// What a random input is made of, simplest first. Printable ASCII; a
// whole scalar of two, three or four bytes; and single bytes: a
// continuation byte, the first byte of a longer sequence, a byte no
// sequence holds (C0, C1, F5..FF). Each writes at most 4 bytes and returns
// how many.
struct Piece {
  const char *name;
  size_t (*draw)(FuzzedDataProvider &, unsigned char *);
};
constexpr Piece pieces[] = {
    {"printable ASCII",
     [](FuzzedDataProvider &p, unsigned char *out) -> size_t {
       out[0] = p.ConsumeIntegralInRange<unsigned char>(0x20, 0x7E);
       return 1;
     }},
    {"a scalar of two bytes",
     [](FuzzedDataProvider &p, unsigned char *out) { return utf8model::encode(scalarOfLength(p, 2), out); }},
    {"a scalar of three bytes",
     [](FuzzedDataProvider &p, unsigned char *out) { return utf8model::encode(scalarOfLength(p, 3), out); }},
    {"a scalar of four bytes",
     [](FuzzedDataProvider &p, unsigned char *out) { return utf8model::encode(scalarOfLength(p, 4), out); }},
    {"a continuation byte",
     [](FuzzedDataProvider &p, unsigned char *out) -> size_t {
       out[0] = oneOf(p, continuationBytes);
       return 1;
     }},
    {"a first byte",
     [](FuzzedDataProvider &p, unsigned char *out) -> size_t {
       out[0] = oneOf(p, leadBytes);
       return 1;
     }},
    {"a byte no sequence holds",
     [](FuzzedDataProvider &p, unsigned char *out) -> size_t {
       out[0] = oneOf(p, strayBytes);
       return 1;
     }},
};
constexpr unsigned pieceFamilies = sizeof pieces / sizeof pieces[0];

// A random input of at most `longest` bytes: pieces of the case's families
// up to a drawn length, the last one cut there, so inputs end inside a
// sequence too. Returns its length.
size_t drawInput(FuzzedDataProvider &p, unsigned char *out) {
  uint64_t mask = prop::swarm(p, pieceFamilies);
  size_t length = p.ConsumeIntegralInRange<size_t>(0, longest);
  size_t n = 0;
  while (n < length) {
    unsigned char piece[4];
    size_t k = pieces[prop::pick(p, mask)].draw(p, piece);
    size_t take = k < length - n ? k : length - n;
    memcpy(out + n, piece, take);
    n += take;
  }
  return n;
}

// Well-formed bytes: the encodings of scalars drawn from Table 3-7's rows,
// whole, up to a drawn length. Returns their length; `scalars` is their
// count.
size_t drawWellFormed(FuzzedDataProvider &p, unsigned char *out, size_t &scalars) {
  size_t length = p.ConsumeIntegralInRange<size_t>(0, longest);
  size_t n = 0;
  scalars = 0;
  while (n < length) {
    const utf8model::Row &row = table37[p.ConsumeIntegralInRange<size_t>(0, utf8model::rows - 1)];
    unsigned char scalar[4];
    size_t k = utf8model::encode(p.ConsumeIntegralInRange<uint32_t>(row.first, row.last), scalar);
    if (k > length - n)
      break;
    memcpy(out + n, scalar, k);
    n += k;
    ++scalars;
  }
  return n;
}

// The string numbered `index` in bijective base 256: 0 is the empty
// string, then every string of one byte, then of two, so the strings of at
// most k bytes are the numbers below 1 + 256 + ... + 256^k. Returns its
// length.
size_t bijective256(uint64_t index, unsigned char *out) {
  size_t n = 0;
  for (; index > 0; index = (index - 1) / 256)
    out[n++] = static_cast<unsigned char>((index - 1) % 256);
  return n;
}

// A byte at an end of a range or just outside it: low - 1, low, high,
// high + 1, modulo 256, the bytes on both sides of each of its boundaries.
constexpr unsigned edgeChoices = 4;
unsigned char edge(utf8model::Range range, unsigned which) {
  const unsigned char at[edgeChoices] = {static_cast<unsigned char>(range.low - 1), range.low,
                                         range.high, static_cast<unsigned char>(range.high + 1)};
  return at[which];
}

// Box 5's inputs: a row of Table 3-7; each of its bytes at an edge of its
// range; the whole sequence or a proper prefix; at an offset from 60 to 64
// of the run, so the sequence ends before the first block boundary, crosses
// it or starts at it.
constexpr size_t firstOffset = block - 4;
constexpr size_t offsets = block - firstOffset + 1;
constexpr uint64_t rowInputs(const utf8model::Row &row) {
  uint64_t choices = 1;
  for (size_t k = 0; k < row.length; ++k)
    choices *= edgeChoices;
  return choices * row.length * offsets;
}
constexpr uint64_t tableInputs() {
  uint64_t count = 0;
  for (const utf8model::Row &row : table37)
    count += rowInputs(row);
  return count;
}

// The model's decoding of U+FFFD substitution's example in the Standard
// (chapter 3, "U+FFFD Substitution of Maximal Subparts").
bool standardsExample() {
  constexpr unsigned char input[] = {0x61, 0xF1, 0x80, 0x80, 0xE1, 0x80, 0xC2,
                                     0x62, 0x80, 0x63, 0x80, 0xBF, 0x64};
  constexpr uint32_t output[] = {0x61, 0xFFFD, 0xFFFD, 0xFFFD, 0x62, 0xFFFD, 0x63, 0xFFFD, 0xFFFD, 0x64};
  uint32_t got[sizeof input];
  size_t count = utf8model::decode(input, sizeof input, got);
  bool holds = count == sizeof output / sizeof output[0] && memcmp(got, output, sizeof output) == 0;
  if (!holds) {
    char text[sizeof input * 7 + 1] = "";
    size_t at = 0;
    for (size_t i = 0; i < count; ++i)
      at += static_cast<size_t>(snprintf(text + at, sizeof text - at, " %04X", got[i]));
    prop::explain("the model reads%s", text);
  }
  return holds;
}

// One owned result: a new string (count 1, one more live cell) or, with
// no byte, the persistent empty one (count 0, no cell), as idris_rt.h's
// from_bytes and from_utf8 say; released, the live cells are as they were.
template <typename Make> bool oneOwnedResult(const char *operation, Make make) {
  uint64_t before = idris_rt_live_cells();
  const idris_rt_str *s = make();
  uint32_t count = s->header.count;
  uint64_t made = idris_rt_live_cells() - before;
  bool owned = s->bytes == 0 ? count == 0 && made == 0 : count == 1 && made == 1;
  bool empty = s->bytes == 0;
  idris_rt_str_release(s);
  bool released = idris_rt_live_cells() == before;
  if (!(owned && released))
    prop::explain("%s: a result of %s with count %u, %llu cells made, %s after its release", operation,
                  empty ? "no byte" : "some bytes", count, static_cast<unsigned long long>(made),
                  released ? "none left" : "some left");
  return owned && released;
}

} // namespace

int main(int argc, char **argv) {
  prop::Run run(argc, argv);

  run.box("box: the model gives the Standard's example its U+FFFDs", 1,
          [](uint64_t) { return standardsExample(); });

  run.property("from_bytes: Table 3-7's scalars, one U+FFFD per maximal subpart",
               [](FuzzedDataProvider &p, prop::Tally &tally) {
                 unsigned char input[longest];
                 size_t n = drawInput(p, input);
                 tally.classify(Decoded(input, n).same(input, n) ? "well-formed" : "ill-formed");
                 return fromBytesIsTheModel(input, n);
               });

  run.box("box: every byte string of at most 2 bytes", 1 + 256 + 256 * 256, [](uint64_t index) {
    unsigned char input[2];
    return fromBytesIsTheModel(input, bijective256(index, input));
  });

  // Each pair of bytes at offsets 62, 63 and 64: ending at the first
  // boundary, across it, starting at it.
  run.box("box: every byte pair across a 64-byte block boundary", 3 * 256 * 256, [](uint64_t index) {
    unsigned char input[runLength];
    memset(input, 'x', sizeof input);
    size_t at = block - 2 + index / (256 * 256);
    input[at] = static_cast<unsigned char>(index / 256 % 256);
    input[at + 1] = static_cast<unsigned char>(index % 256);
    return fromBytesIsTheModel(input, sizeof input);
  });

  run.box("box: every row of Table 3-7 and its truncations around a block boundary", tableInputs(),
          [](uint64_t index) {
            size_t row = 0;
            for (; index >= rowInputs(table37[row]); ++row)
              index -= rowInputs(table37[row]);
            const utf8model::Row &r = table37[row];
            size_t at = firstOffset + index % offsets;
            index /= offsets;
            size_t length = 1 + index % r.length;
            index /= r.length;
            unsigned char input[runLength];
            memset(input, 'x', sizeof input);
            for (size_t k = 0; k < length; ++k, index /= edgeChoices)
              input[at + k] = edge(r.bytes[k], static_cast<unsigned>(index % edgeChoices));
            return fromBytesIsTheModel(input, sizeof input);
          });

  run.property("from_utf8, utf8_count: well-formed bytes as they are, counted",
               [](FuzzedDataProvider &p, prop::Tally &) {
                 unsigned char input[longest];
                 size_t scalars = 0;
                 size_t n = drawWellFormed(p, input, scalars);
                 const char *bytes = reinterpret_cast<const char *>(input);
                 const idris_rt_str *s = idris_rt_str_from_utf8(bytes, n);
                 bool holds = s->bytes == n && memcmp(idris_rt_str_bytes(s), input, n) == 0 &&
                              s->scalars == scalars && idris_rt_utf8_count(bytes, n) == scalars;
                 if (!holds) {
                   prop::explain("%zu scalars, %s", scalars, Hex(input, n).text);
                   prop::explain("from_utf8: %llu scalars, %s; utf8_count: %zu",
                                 static_cast<unsigned long long>(s->scalars),
                                 Hex(idris_rt_str_bytes(s), s->bytes).text, idris_rt_utf8_count(bytes, n));
                 }
                 idris_rt_str_release(s);
                 return holds;
               });

  run.property("every operation borrows its argument and returns one owned result",
               [](FuzzedDataProvider &p, prop::Tally &) {
                 unsigned char any[longest];
                 size_t n = drawInput(p, any);
                 unsigned char wellFormed[longest];
                 size_t scalars = 0;
                 size_t m = drawWellFormed(p, wellFormed, scalars);
                 return oneOwnedResult("from_bytes", [&] {
                          return idris_rt_str_from_bytes(reinterpret_cast<const char *>(any), n);
                        }) &&
                        oneOwnedResult("from_utf8", [&] {
                          return idris_rt_str_from_utf8(reinterpret_cast<const char *>(wellFormed), m);
                        });
               });

  return run.finish();
}
