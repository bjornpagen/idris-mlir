// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The one way out of a process, and the C entries that end a program: its
// crashes at a site, its exit, and running out of memory.
// PIN(runtime-quarantine) — see PINS.md
#include "End/End.h"
#include "Io/Io.h"
#include "Platform/Platform.h"
#include "cpu_features.h"
#include "idris_rt.h"

#include <concepts>
#include <stdarg.h>
#include <stddef.h>
#include <stdint.h>
#include <stdio.h>

#include <__verbose_abort>
#include <string_view>

namespace {

using namespace rt::end;

// The name every message begins with; empty until a host of the runtime
// sets it, which each does before anything can end.
const char *programName = "";
size_t programNameLength = 0;

// A message, a run of pieces written to standard error with write(2): what
// an ending says, which allocates nothing and formats its numbers into its
// own room, so that the fault handler may say it.
class Message {
public:
  IDRIS_RT_BASELINE void add(const char *bytes, size_t length) noexcept {
    pieces[count++] = {bytes, length};
  }
  template <size_t N>
  IDRIS_RT_BASELINE void add(const char (&text)[N]) noexcept {
    add(text, N - 1);
  }
  IDRIS_RT_BASELINE void add(const idris_rt_text *text) noexcept {
    add(text->bytes, text->length);
  }
  void add(std::string_view text) noexcept { add(text.data(), text.size()); }

  // A NUL-terminated text a library gave.
  void addTerminated(const char *text) noexcept {
    size_t length = 0;
    while (text[length] != '\0')
      ++length;
    add(text, length);
  }

  // A number's decimal digits, written into this message's own room.
  IDRIS_RT_BASELINE void unsignedNumber(uint64_t value) noexcept { number(value, false); }
  void signedNumber(int64_t value) noexcept {
    uint64_t magnitude =
        value < 0 ? 0 - static_cast<uint64_t>(value) : static_cast<uint64_t>(value);
    number(magnitude, value < 0);
  }

  // `file:line:col: `, the site's place.
  void place(const Site &site) noexcept {
    add(site.file);
    add(":");
    unsignedNumber(site.line);
    add(":");
    unsignedNumber(site.column);
    add(": ");
  }

  // `<program>: fatal: `, the pieces, and a newline, on standard error. A
  // write that fails here changes nothing of how the process ends.
  IDRIS_RT_BASELINE void write() const noexcept {
    static constexpr char fatal[] = ": fatal: ";
    (void)rt::platform::writeAll(2, programName, programNameLength);
    (void)rt::platform::writeAll(2, fatal, sizeof fatal - 1);
    for (size_t i = 0; i < count; ++i)
      (void)rt::platform::writeAll(2, pieces[i].bytes, pieces[i].length);
    (void)rt::platform::writeAll(2, "\n", 1);
  }

private:
  [[gnu::always_inline]] void number(uint64_t value, bool negative) noexcept {
    char *end = digits[numbers] + sizeof digits[numbers];
    char *at = end;
    do {
      *--at = static_cast<char>('0' + value % 10);
      value /= 10;
    } while (value != 0);
    if (negative)
      *--at = '-';
    ++numbers;
    add(at, static_cast<size_t>(end - at));
  }

  struct Piece {
    const char *bytes;
    size_t length;
  };
  // The longest message an ending says: a processor that lacks every one of
  // the 64 bits a program may require, each named or numbered, and the two
  // pieces around them.
  static constexpr size_t featureBits = 64;
  Piece pieces[2 + 2 * featureBits];
  size_t count = 0;
  // Room for every number a message holds, each the 20 digits of the largest
  // and a sign: at most one per feature bit.
  char digits[featureBits][21];
  size_t numbers = 0;
};

// An ending that leaves by an exit status: from the table, or its own.
template <class E>
concept Exits = requires(const E &ending) {
  { statusOf(ending) } -> std::same_as<uint8_t>;
};

// An ending that leaves by a signal, once its message is written.
template <class E>
concept Raises = requires {
  { E::signal } -> std::convertible_to<idr::endings::EndingSignal>;
};

// What an ending says: a silent one (a return, an exit, a reader gone)
// says nothing.
template <class E>
concept Says = requires(const E &ending, Message &message) { say(message, ending); };

IDRIS_RT_BASELINE uint8_t fixed(idr::endings::FixedStatus status) noexcept {
  return idr::endings::statusCode[static_cast<size_t>(status)];
}

uint8_t statusOf(const Returned &) noexcept { return fixed(idr::endings::FixedStatus::Returned); }
uint8_t statusOf(const Exited &ending) noexcept { return ending.status; }
uint8_t statusOf(const Failed &) noexcept { return fixed(idr::endings::FixedStatus::Crashed); }
uint8_t statusOf(const Said &) noexcept { return fixed(idr::endings::FixedStatus::Crashed); }
uint8_t statusOf(const Unreportable &) noexcept { return fixed(idr::endings::FixedStatus::Crashed); }
uint8_t statusOf(const OutOfMemory &) noexcept { return fixed(idr::endings::FixedStatus::OutOfMemory); }
IDRIS_RT_BASELINE uint8_t statusOf(const MissingFeatures &) noexcept {
  return fixed(idr::endings::FixedStatus::CannotRun);
}
IDRIS_RT_BASELINE uint8_t statusOf(const WrongPage &) noexcept {
  return fixed(idr::endings::FixedStatus::CannotRun);
}

// The cause's phrase from the table, after its site's place; a missing
// clause's names the function its site lies in.
void say(Message &m, const Failed &ending) noexcept {
  m.place(ending.site);
  auto at = static_cast<size_t>(ending.cause);
  m.add(idr::endings::causePhrase[at]);
  if (idr::endings::causeNaming[at] == idr::endings::CauseNaming::WithFunction) {
    m.add(" ");
    m.add(ending.site.function);
  }
}

void say(Message &m, const Said &ending) noexcept {
  m.place(ending.site);
  m.add(idris_rt_str_bytes(ending.message), ending.message->bytes);
}

void say(Message &m, const Unreportable &ending) noexcept {
  m.place(ending.site);
  m.add("exit status ");
  m.signedNumber(ending.status);
  m.add(" cannot be reported");
}

void say(Message &m, const OutOfMemory &) noexcept { m.add("out of memory"); }

// Each missing feature by its name, and a bit no feature of the target's
// list names (a program built against another list) by its number.
IDRIS_RT_BASELINE void say(Message &m, const MissingFeatures &ending) noexcept {
  m.add("this processor lacks");
#define IDRIS_RT_CPU_NAME(bit, test, name)                                                       \
  if ((ending.missing >> (bit) & 1) != 0)                                                        \
    m.add(" " name);
  IDRIS_RT_CPU_FEATURES(IDRIS_RT_CPU_NAME)
#undef IDRIS_RT_CPU_NAME
#define IDRIS_RT_CPU_BIT(bit, test, name) | uint64_t{1} << (bit)
  constexpr uint64_t named = 0 IDRIS_RT_CPU_FEATURES(IDRIS_RT_CPU_BIT);
#undef IDRIS_RT_CPU_BIT
  for (uint64_t unnamed = ending.missing & ~named; unnamed != 0; unnamed &= unnamed - 1) {
    m.add(" bit ");
    m.unsignedNumber(static_cast<uint64_t>(__builtin_ctzll(unnamed)));
  }
  m.add(", which the program was compiled to use");
}

IDRIS_RT_BASELINE void say(Message &m, const WrongPage &ending) noexcept {
  m.add("the runtime is built for a ");
  m.unsignedNumber(ending.built);
  m.add("-byte page, and this system has a ");
  m.unsignedNumber(ending.system);
  m.add("-byte page");
}

// An internal error: its phrase from the table, then the detail it carries.
void internal(Message &m, idr::endings::Internal which) noexcept {
  m.add("internal error: ");
  m.add(idr::endings::internalPhrase[static_cast<size_t>(which)]);
}

void say(Message &m, const StackExhausted &) noexcept {
  internal(m, idr::endings::Internal::StackExhausted);
}
void say(Message &m, const CellsLeaked &ending) noexcept {
  internal(m, idr::endings::Internal::CellsLeaked);
  m.add(" ");
  m.unsignedNumber(ending.cells);
}
void say(Message &m, const CountOfDeadCell &) noexcept {
  internal(m, idr::endings::Internal::CountOfDeadCell);
}
void say(Message &m, const FrameBoundExceeded &ending) noexcept {
  internal(m, idr::endings::Internal::FrameBoundExceeded);
  m.add(" ");
  m.add(ending.function);
  m.add(" held ");
  m.unsignedNumber(ending.held);
  m.add(", its bound ");
  m.unsignedNumber(ending.bound);
}
void say(Message &m, const AllocatorFailed &ending) noexcept {
  internal(m, idr::endings::Internal::AllocatorFailed);
  m.add(" ");
  m.addTerminated(ending.text);
}
void say(Message &m, const LibraryFailed &ending) noexcept {
  internal(m, idr::endings::Internal::LibraryFailed);
  m.add(" ");
  m.addTerminated(ending.text);
}

} // namespace

namespace rt::end {

IDRIS_RT_BASELINE void name(const char *bytes, size_t length) noexcept {
  programName = bytes;
  programNameLength = length;
}

template <class E>
[[noreturn]] IDRIS_RT_BASELINE void end(const E &ending) noexcept {
  static_assert(Exits<E> != Raises<E>, "an ending leaves by a status or by a signal");
  // What the program wrote before its end, in the order it wrote it:
  // standard output's pending bytes, then its files, closed.
  if constexpr (E::cleans != Cleans::Nothing)
    (void)rt::io::writePending();
  if constexpr (E::cleans == Cleans::Everything)
    rt::io::releaseHandles();
  if constexpr (Says<E>) {
    Message message;
    say(message, ending);
    message.write();
  }
  if constexpr (Raises<E>)
    rt::platform::raiseSignal(E::signal);
  else
    rt::platform::exitProcess(statusOf(ending));
}

template void end(const Returned &) noexcept;
template void end(const Exited &) noexcept;
template void end(const Failed &) noexcept;
template void end(const Said &) noexcept;
template void end(const Unreportable &) noexcept;
template void end(const OutOfMemory &) noexcept;
template void end(const MissingFeatures &) noexcept;
template void end(const WrongPage &) noexcept;
template void end(const Piped &) noexcept;
template void end(const StackExhausted &) noexcept;
template void end(const CellsLeaked &) noexcept;
template void end(const CountOfDeadCell &) noexcept;
template void end(const FrameBoundExceeded &) noexcept;
template void end(const AllocatorFailed &) noexcept;
template void end(const LibraryFailed &) noexcept;

} // namespace rt::end

namespace {

// A site as the C ABI passes it, the lowering's static texts and the line
// and column as 32-bit integers, read once into its type.
rt::end::Site siteOf(const idris_rt_text *function, const idris_rt_text *file, int32_t line,
                     int32_t column) {
  return {function, file, static_cast<uint32_t>(line), static_cast<uint32_t>(column)};
}

} // namespace

// A crash of a cause of the closed set, its position in the specification's
// list, at its site: the function it lies in, its file, line and column,
// each file and function one static text of the program.
extern "C" void idris_rt_crash_at(int32_t cause, const idris_rt_text *function,
                                  const idris_rt_text *file, int32_t line, int32_t column) {
  rt::end::end(rt::end::Failed{static_cast<idr::endings::CrashCause>(cause),
                               siteOf(function, file, line, column)});
}

// A crash of the text a trusted library gave idris_crash, at its site.
extern "C" void idris_rt_crash_message_at(const idris_rt_str *message,
                                          const idris_rt_text *function,
                                          const idris_rt_text *file, int32_t line, int32_t column) {
  rt::end::end(rt::end::Said{message, siteOf(function, file, line, column)});
}

// A crash at an exit whose status, outside 0 to 255, no parent could read:
// the guard before the exit found it so, and names it.
extern "C" void idris_rt_unreportable_at(int64_t status, const idris_rt_text *function,
                                         const idris_rt_text *file, int32_t line, int32_t column) {
  rt::end::end(rt::end::Unreportable{status, siteOf(function, file, line, column)});
}

// Base's exit, with a status a parent reads: a byte, since the lowering ends
// an exit of any other status at its site first (idris_rt_unreportable_at)
// and passes the rest as one. What the program wrote is written and its
// files closed, and the process ends with it.
extern "C" void idris_rt_exit(uint8_t status) { rt::end::end(rt::end::Exited{status}); }

// Memory no allocation can meet, for a size the lowering found too large or
// a tool's own allocator that ran out: the out-of-memory ending.
extern "C" void idris_rt_out_of_memory(void) { rt::end::end(rt::end::OutOfMemory{}); }

// libc++'s hardening, on in every configuration, calls this when one of
// its checks fails, in the runtime and in idris-mlir alike (it overrides
// libc++'s own, which is weak): a bug of the runtime's or the compiler's,
// whichever host runs, ended as the runtime's internal error with the
// check's own text. Not in a signal handler, so the C library may format it.
_LIBCPP_BEGIN_NAMESPACE_STD
void __libcpp_verbose_abort(const char *format, ...) _LIBCPP_VERBOSE_ABORT_NOEXCEPT {
  static char text[1024];
  va_list arguments;
  va_start(arguments, format);
  vsnprintf(text, sizeof text, format, arguments);
  va_end(arguments);
  rt::end::end(rt::end::LibraryFailed{text});
}
_LIBCPP_END_NAMESPACE_STD
