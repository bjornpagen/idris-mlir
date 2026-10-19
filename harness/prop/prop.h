// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The runtime's property programs: each case draws its values through
// compiler-rt's FuzzedDataProvider over bytes of splitmix64 seeded per case,
// so `--seed S --case I` replays one; a failing case is shrunk by halving its
// bytes; each property's classes go to the report file --report names, never
// into it. A program's transcript is its property lines only.
//
// Header-only, and nothing in it needs the C++ library at link time: a
// property program links as a program does, with none.
#pragma once
#include <fuzzer/FuzzedDataProvider.h>
#include <stddef.h>
#include <stdint.h>

#include "idris_rt.h"   // idris_rt_flush, for captureStdout

#include <errno.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

namespace prop {

// The bytes one case draws from: room for the largest case a property of
// this wave draws (two operands of 8 limbs are 128 bytes; a string of 320
// bytes; a sequence of 300 operations of a few bytes each), with a margin.
inline constexpr size_t caseBytes = 1024;
// The distinct labels one property counts; more are counted as "other".
inline constexpr unsigned classLimit = 64;
// The properties and boxes one program reports.
inline constexpr unsigned propertyLimit = 64;

// splitmix64 (Vigna 2015): state += 0x9E3779B97F4A7C15, then the state mixed
// by (z ^ z >> 30) * 0xBF58476D1CE4E5B9, (z ^ z >> 27) * 0x94D049BB133111EB,
// z ^ z >> 31. From state 0 its outputs are 0xE220A8397B1DCDAF,
// 0x6E789E6AA1B965F4, 0x06C45D188009454F.
inline uint64_t splitmix64(uint64_t &state) {
  state += 0x9E3779B97F4A7C15u;
  uint64_t z = state;
  z = (z ^ z >> 30) * 0xBF58476D1CE4E5B9u;
  z = (z ^ z >> 27) * 0x94D049BB133111EBu;
  return z ^ z >> 31;
}
// Output `index` (from 0) of splitmix64 started at `seed`:
// mix(seed + (index + 1) * 0x9E3779B97F4A7C15). harness/Gen.idr's caseSeed.
inline uint64_t caseSeed(uint64_t seed, uint64_t index) {
  uint64_t state = seed + index * 0x9E3779B97F4A7C15u;
  return splitmix64(state);
}
// `length` bytes of splitmix64 started at caseSeed(seed, index), each
// output's eight bytes least significant first (by shifts, not memcpy).
inline void fillCase(uint64_t seed, uint64_t index, uint8_t *bytes, size_t length) {
  uint64_t state = caseSeed(seed, index);
  for (size_t at = 0; at < length; at += 8) {
    uint64_t output = splitmix64(state);
    for (size_t k = 0; k < 8 && at + k < length; ++k)
      bytes[at + k] = static_cast<uint8_t>(output >> (8 * k));
  }
}

// A case's class, for the report: the last label given.
class Tally {
public:
  void classify(const char *label) { label_ = label; }   // a string literal
  const char *label() const { return label_; }          // nullptr when unclassified
private:
  const char *label_ = nullptr;
};

// Swarm testing: `families` (1 to 64) bits, bit i set when the provider's
// next ConsumeBool() is true; never 0: when every bit came out clear, bit 0,
// the simplest family, is set. An exhausted provider gives exactly bit 0.
inline uint64_t swarm(FuzzedDataProvider &provider, unsigned families) {
  uint64_t mask = 0;
  for (unsigned i = 0; i < families; ++i)
    mask |= static_cast<uint64_t>(provider.ConsumeBool()) << i;
  return mask | static_cast<uint64_t>(mask == 0);
}
// One family the mask keeps, uniform over its set bits (one
// ConsumeIntegralInRange over their count); the lowest set bit when the
// provider is exhausted. mask is not 0.
inline unsigned pick(FuzzedDataProvider &provider, uint64_t mask) {
  auto kept = static_cast<unsigned>(__builtin_popcountll(mask));
  for (unsigned skip = provider.ConsumeIntegralInRange<unsigned>(0, kept - 1); skip > 0; --skip)
    mask &= mask - 1;
  return static_cast<unsigned>(__builtin_ctzll(mask));
}

namespace detail {
// What explain() has said of the case or input running: whole lines, each
// ending in '\n', then a NUL, in a buffer that is cleared before each case
// and input. A line past its room is cut, and once no line fits, nothing
// more is kept.
struct Explanation {
  char text[4096];
  size_t used;
};
inline Explanation explanation;
inline void clearExplanation() {
  explanation.used = 0;
  explanation.text[0] = '\0';
}
} // namespace detail

// A line (printf format) saying why the current case or input fails; the
// lines of the case or input a property reports are printed under it.
__attribute__((format(printf, 1, 2))) inline void explain(const char *format, ...) {
  detail::Explanation &e = detail::explanation;
  // The room a line needs at least: its '\n' and the NUL after it.
  if (e.used + 2 > sizeof e.text)
    return;
  va_list arguments;
  va_start(arguments, format);
  vsnprintf(e.text + e.used, sizeof e.text - 1 - e.used, format, arguments);
  va_end(arguments);
  e.used += strlen(e.text + e.used);
  e.text[e.used++] = '\n';
  e.text[e.used] = '\0';
}

// Runs write() with standard output (fd 1) sent to a fresh tmpfile(): stdio
// and the runtime's output buffer (idris_rt_flush) are flushed before the
// switch and after write(), fd 1 is restored, and the bytes written are
// copied into out, at most `capacity`. Returns the count written, which may
// exceed capacity.
template <typename Write> size_t captureStdout(Write write, char *out, size_t capacity) {
  fflush(stdout);
  idris_rt_flush();
  FILE *file = tmpfile();
  int saved = dup(1);
  // The system may refuse a file or a descriptor; without them there is no
  // capture to check, so the program ends as a crash rather than a verdict.
  if (file == nullptr || saved < 0) {
    perror("prop: captureStdout");
    abort();
  }
  int capture = fileno(file);
  dup2(capture, 1);
  write();
  fflush(stdout);
  idris_rt_flush();
  dup2(saved, 1);
  close(saved);
  auto written = static_cast<size_t>(lseek(capture, 0, SEEK_END));
  lseek(capture, 0, SEEK_SET);
  size_t copied = 0;
  ssize_t n = 0;
  while (copied < capacity && (n = read(capture, out + copied, capacity - copied)) > 0)
    copied += static_cast<size_t>(n);
  fclose(file);
  return written;
}

class Run {
public:
  // PROGRAM [--seed S] [--cases N] [--case I [--bytes L]] [--report FILE];
  // defaults: seed 1, 1000 cases, every case, caseBytes, no report. Any other
  // argument: a usage line on stderr and exit status 2.
  Run(int argc, char **argv) : program_(argv[0]) {
    uint64_t cases = 1000;
    bool replay = false;
    // Every option takes a value: an option is argv[at], its value argv[at + 1].
    for (int at = 1; at < argc; at += 2) {
      const char *option = argv[at];
      const char *text = valueOf(argc, argv, at + 1);
      if (equal(option, "--seed")) {
        seed_ = number(text, 0, UINT64_MAX);
      } else if (equal(option, "--cases")) {
        // A run of no case would hold vacuously.
        cases = number(text, 1, UINT64_MAX);
      } else if (equal(option, "--case")) {
        // The case after the last has no index, so [I, I + 1) is never empty.
        first_ = number(text, 0, UINT64_MAX - 1);
        replay = true;
        // --bytes belongs to --case, as its usage writes it.
        if (at + 2 < argc && equal(argv[at + 2], "--bytes")) {
          bytes_ = static_cast<size_t>(number(valueOf(argc, argv, at + 3), 0, caseBytes));
          at += 2;
        }
      } else if (equal(option, "--report")) {
        report_ = text;
      } else {
        usage();
      }
    }
    // The cases a property runs, half-open: every case, or case I alone.
    end_ = replay ? first_ + 1 : cases;
  }
  // body(FuzzedDataProvider &, Tally &) -> bool, true when the property
  // holds, on cases 0 to N - 1 (or case I alone), each over fillCase(S, i)
  // and its first caseBytes (or L) bytes. At the first case that fails, the
  // byte count is halved while the case still fails, then that case runs
  // once more for its explain() lines. Prints "<name>: ok", or
  // "<name>: failed", "  | case I of seed S, L bytes: rerun with --seed S
  // --case I --bytes L" and "  | <line>" for each explanation. Stdout is
  // flushed after every line.
  template <typename Body> void property(const char *name, Body body) {
    Entry &entry = enter(name, Kind::Property);
    uint8_t bytes[caseBytes];
    for (uint64_t index = first_; index < end_; ++index) {
      fillCase(seed_, index, bytes, bytes_);
      Tally tally;
      bool holds = holdsOn(body, bytes, bytes_, tally);
      ++entry.runs;
      ++rowOf(entry, tally.label() != nullptr ? tally.label() : "unclassified").count;
      if (holds)
        continue;
      // Each half is a prefix of the same bytes, so it needs no refill.
      size_t length = bytes_;
      while (length > 0 && !holdsOn(body, bytes, length / 2, tally))
        length /= 2;
      holdsOn(body, bytes, length, tally);
      line("%s: failed", name);
      line("  | case %llu of seed %llu, %zu bytes: rerun with --seed %llu --case %llu --bytes %zu",
           static_cast<unsigned long long>(index), static_cast<unsigned long long>(seed_), length,
           static_cast<unsigned long long>(seed_), static_cast<unsigned long long>(index), length);
      explained();
      held_ = false;
      return;
    }
    line("%s: ok", name);
  }
  // body(uint64_t input) -> bool on every input in [0, count), whatever
  // --case says. Prints "<name>: ok", or "<name>: failed", "  | input I" and
  // the explanation lines of the first input that fails.
  template <typename Body> void box(const char *name, uint64_t count, Body body) {
    enter(name, Kind::Box).runs = count;
    for (uint64_t input = 0; input < count; ++input) {
      detail::clearExplanation();
      if (body(input))
        continue;
      line("%s: failed", name);
      line("  | input %llu", static_cast<unsigned long long>(input));
      explained();
      held_ = false;
      return;
    }
    line("%s: ok", name);
  }
  // Writes the report when --report was given; returns 0 when every
  // property and box held, else 1.
  int finish() {
    if (report_ != nullptr)
      writeReport();
    return held_ ? 0 : 1;
  }

private:
  // A property samples cases, which fall into classes; a box runs each
  // input of a set: two kinds of check, reported as two kinds of line.
  enum class Kind { Property, Box };
  struct Row {
    const char *label;
    uint64_t count;
  };
  struct Entry {
    const char *name;
    Kind kind;
    // The cases a property ran, or the inputs of a box.
    uint64_t runs;
    // The labels counted, then "other" once classLimit are.
    Row rows[classLimit + 1];
    unsigned used;
  };

  [[noreturn]] void usage() {
    fprintf(stderr, "usage: %s [--seed S] [--cases N] [--case I [--bytes L]] [--report FILE]\n",
            program_);
    exit(2);
  }
  static bool equal(const char *a, const char *b) { return strcmp(a, b) == 0; }
  // The value at argv[at], or the usage line when the arguments end first.
  const char *valueOf(int argc, char **argv, int at) {
    if (at >= argc)
      usage();
    return argv[at];
  }
  // A decimal number in [low, high], or the usage line.
  uint64_t number(const char *text, uint64_t low, uint64_t high) {
    if (text[0] < '0' || text[0] > '9')
      usage();
    char *end = nullptr;
    errno = 0;
    unsigned long long value = strtoull(text, &end, 10);
    if (*end != '\0' || errno != 0 || value < low || value > high)
      usage();
    return value;
  }

  __attribute__((format(printf, 2, 3))) void line(const char *format, ...) {
    va_list arguments;
    va_start(arguments, format);
    vprintf(format, arguments);
    va_end(arguments);
    putchar('\n');
    fflush(stdout);
  }
  void explained() {
    for (const char *at = detail::explanation.text; *at != '\0';) {
      const char *end = strchr(at, '\n');
      line("  | %.*s", static_cast<int>(end - at), at);
      at = end + 1;
    }
  }

  template <typename Body> static bool holdsOn(Body &body, const uint8_t *bytes, size_t length, Tally &tally) {
    detail::clearExplanation();
    FuzzedDataProvider provider(bytes, length);
    return body(provider, tally);
  }

  Entry &enter(const char *name, Kind kind) {
    // More checks than the report has room for is a fault of the program,
    // not a verdict on the runtime.
    if (entryCount_ == propertyLimit) {
      fprintf(stderr, "prop: more than %u properties and boxes in one program\n", propertyLimit);
      abort();
    }
    Entry &entry = entries_[entryCount_++];
    entry.name = name;
    entry.kind = kind;
    entry.runs = 0;
    entry.used = 0;
    return entry;
  }
  // The row of `label`; past classLimit labels, a new one is counted as
  // "other", in the row kept for it.
  Row &rowOf(Entry &entry, const char *label) {
    for (unsigned i = 0; i < entry.used; ++i)
      if (equal(entry.rows[i].label, label))
        return entry.rows[i];
    if (entry.used >= classLimit && !equal(label, "other"))
      return rowOf(entry, "other");
    entry.rows[entry.used] = Row{label, 0};
    return entry.rows[entry.used++];
  }

  void writeReport() {
    FILE *out = fopen(report_, "w");
    // The verdicts stand without the report; the line on stderr is what
    // shows it is missing.
    if (out == nullptr) {
      fprintf(stderr, "prop: cannot write the report %s\n", report_);
      return;
    }
    fprintf(out, "seed %llu, %llu cases a property\n", static_cast<unsigned long long>(seed_),
            static_cast<unsigned long long>(end_ - first_));
    for (unsigned e = 0; e < entryCount_; ++e) {
      Entry &entry = entries_[e];
      if (entry.kind == Kind::Box) {
        fprintf(out, "%s: box of %llu inputs\n", entry.name, static_cast<unsigned long long>(entry.runs));
        continue;
      }
      // Labels in byte order, by insertion: there are at most classLimit + 1.
      for (unsigned i = 1; i < entry.used; ++i)
        for (unsigned j = i; j > 0 && strcmp(entry.rows[j - 1].label, entry.rows[j].label) > 0; --j) {
          Row moved = entry.rows[j];
          entry.rows[j] = entry.rows[j - 1];
          entry.rows[j - 1] = moved;
        }
      unsigned once = 0;
      for (unsigned i = 0; i < entry.used; ++i)
        once += entry.rows[i].count == 1;
      // The Good-Turing estimate of the chance that the next case falls in
      // a class not yet seen; runs is at least 1, since no run is empty.
      fprintf(out, "%s: n=%llu classes=%u f1=%u f1/n=%.4f\n", entry.name,
              static_cast<unsigned long long>(entry.runs), entry.used, once,
              static_cast<double>(once) / static_cast<double>(entry.runs));
      for (unsigned i = 0; i < entry.used; ++i)
        fprintf(out, "  %s: %llu\n", entry.rows[i].label, static_cast<unsigned long long>(entry.rows[i].count));
    }
    fclose(out);
  }

  const char *program_;
  uint64_t seed_ = 1;
  uint64_t first_ = 0;
  uint64_t end_ = 0;
  size_t bytes_ = caseBytes;
  const char *report_ = nullptr;
  bool held_ = true;
  Entry entries_[propertyLimit];
  unsigned entryCount_ = 0;
};

} // namespace prop
