// Standard output and input, and crash. Static storage and the stack
// only: the only libc symbols are write, read, _exit and getenv.
// PIN(runtime-quarantine) — see PINS.md

#include "internal.h"

#include <simdutf.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

namespace {

constexpr size_t bufferSize = 4096;

// Written through a volatile pointer, so that LLVM makes no memcpy of the
// copy loop.
char output[bufferSize];
size_t outputLength = 0;

char input[bufferSize];
size_t inputPosition = 0;
size_t inputLength = 0;
// Set once a read met the end of input: what C's feof reports.
bool inputEnded = false;

void putBytes(const char *p, size_t n) {
  if (outputLength + n > bufferSize)
    idris_rt_flush();
  if (n > bufferSize) {
    rt::writeAll(1, p, n);
    return;
  }
  volatile char *to = output + outputLength;
  for (size_t i = 0; i < n; ++i)
    to[i] = p[i];
  outputLength += n;
}

// The next input byte, or -1 at the end of input. Pending output is written
// before the program blocks reading.
int32_t peek() {
  if (inputPosition >= inputLength) {
    idris_rt_flush();
    ssize_t got = read(0, input, bufferSize);
    inputLength = got > 0 ? static_cast<size_t>(got) : 0;
    inputPosition = 0;
  }
  if (inputPosition < inputLength)
    return static_cast<unsigned char>(input[inputPosition]);
  inputEnded = true;
  return -1;
}

// A growable line being read: on the stack up to a page, then raw memory.
struct Line {
  char inline_[bufferSize];
  char *bytes = inline_;
  size_t length = 0;
  size_t capacity = bufferSize;
  ~Line() {
    if (bytes != inline_)
      rt::release(bytes);
  }
  void push(char c) {
    if (length == capacity) {
      auto *grown = static_cast<char *>(rt::allocate(capacity * 2));
      memcpy(grown, bytes, length);
      if (bytes != inline_)
        rt::release(bytes);
      bytes = grown;
      capacity *= 2;
    }
    bytes[length++] = c;
  }
};

// The string of n bytes at p, ill-formed UTF-8 replaced by U+FFFD one byte
// at a time, as Chez's decoder replaces it.
const idris_rt_str *decoded(const char *p, size_t n) {
  if (simdutf::validate_utf8(p, n))
    return rt::stringOf(p, n);
  static constexpr char replacement[] = "\xEF\xBF\xBD";
  Line out;
  while (n > 0) {
    simdutf::result checked = simdutf::validate_utf8_with_errors(p, n);
    size_t good = checked.error == simdutf::SUCCESS ? n : checked.count;
    for (size_t i = 0; i < good; ++i)
      out.push(p[i]);
    p += good;
    n -= good;
    if (n > 0) {
      for (char c : replacement)
        if (c != '\0')
          out.push(c);
      ++p;
      --n;
    }
  }
  return rt::stringOf(out.bytes, out.length);
}

// The live cells on standard error when IDRIS_RT_LIVE is "1", in one write:
// how a test sees that a program frees every cell it allocates. An
// evaluation child counts nothing, and its standard error is the compiler's.
void reportLiveCells() {
  if (rt::arenaActive)
    return;
  const char *setting = getenv("IDRIS_RT_LIVE");
  if (setting == nullptr || setting[0] != '1' || setting[1] != '\0')
    return;
  static constexpr char prefix[] = "idris-rt: live cells ";
  constexpr size_t prefixLength = sizeof prefix - 1;
  char line[prefixLength + rt::intTextMax + 1];
  char *end = line + sizeof line;
  end[-1] = '\n';
  char *start = rt::formatUnsigned(idris_rt_live_cells(), end - 1) - prefixLength;
  volatile char *to = start;
  for (size_t i = 0; i < prefixLength; ++i)
    to[i] = prefix[i];
  rt::writeAll(2, start, static_cast<size_t>(end - start));
}

} // namespace

void rt::writeAll(int fd, const char *p, size_t n) {
  while (n > 0) {
    ssize_t written = write(fd, p, n);
    size_t step = written > 0 ? static_cast<size_t>(written) : n;
    p += step;
    n -= step;
  }
}

char *rt::formatUnsigned(uint64_t value, char *end) {
  do {
    *--end = static_cast<char>('0' + value % 10);
    value /= 10;
  } while (value != 0);
  return end;
}

char *rt::formatSigned(int64_t value, char *end) {
  uint64_t magnitude = value < 0 ? 0 - static_cast<uint64_t>(value) : static_cast<uint64_t>(value);
  char *start = formatUnsigned(magnitude, end);
  if (value < 0)
    *--start = '-';
  return start;
}

size_t rt::encodeUtf8(int32_t c, char *out) {
  auto u = static_cast<uint32_t>(c);
  if (u < 0x80) {
    out[0] = static_cast<char>(u);
    return 1;
  }
  size_t n = u < 0x800 ? 2 : u < 0x10000 ? 3 : 4;
  static constexpr uint32_t prefix[] = {0, 0, 0xC0, 0xE0, 0xF0};
  out[0] = static_cast<char>(prefix[n] | (u >> (6 * (n - 1))));
  for (size_t k = 1; k < n; ++k)
    out[k] = static_cast<char>(0x80 | ((u >> (6 * (n - 1 - k))) & 0x3F));
  return n;
}

extern "C" void idris_rt_flush(void) {
  rt::writeAll(1, output, outputLength);
  outputLength = 0;
}

extern "C" void idris_rt_io_put_str(const idris_rt_str *s) {
  putBytes(idris_rt_str_bytes(s), s->bytes);
}

extern "C" void idris_rt_io_put_char(int32_t c) {
  char bytes[4];
  putBytes(bytes, rt::encodeUtf8(c, bytes));
}

extern "C" void idris_rt_io_put_int_s(int64_t value) {
  char text[rt::intTextMax];
  char *end = text + sizeof text;
  char *start = rt::formatSigned(value, end);
  putBytes(start, static_cast<size_t>(end - start));
}

extern "C" void idris_rt_io_put_int_u(uint64_t value) {
  char text[rt::intTextMax];
  char *end = text + sizeof text;
  char *start = rt::formatUnsigned(value, end);
  putBytes(start, static_cast<size_t>(end - start));
}

extern "C" void idris_rt_io_put_double(double value) {
  char text[rt::doubleTextMax];
  putBytes(text, rt::formatDouble(value, text));
}

extern "C" int32_t idris_rt_io_get_byte(void) {
  int32_t b = peek();
  if (b < 0)
    return 255;
  ++inputPosition;
  return b;
}

extern "C" const idris_rt_str *idris_rt_io_get_line(void) {
  Line line;
  bool cut = false;
  for (int32_t b = peek(); b >= 0; b = peek()) {
    ++inputPosition;
    if (b == '\n')
      break;
    if (b == '\r')
      cut = true;
    if (!cut)
      line.push(static_cast<char>(b));
  }
  return decoded(line.bytes, line.length);
}

extern "C" int32_t idris_rt_io_eof(void) { return inputEnded ? 1 : 0; }

extern "C" void idris_rt_main_return(void) {
  idris_rt_flush();
  reportLiveCells();
}

extern "C" void idris_rt_crash(const char *msg, size_t len) {
  idris_rt_flush();
  rt::writeAll(2, msg, len);
  _exit(IDRIS_RT_CRASHED);
}

extern "C" int32_t idris_rt_int_head_s(int64_t value) {
  char text[rt::intTextMax];
  return *rt::formatSigned(value, text + sizeof text);
}

extern "C" int32_t idris_rt_int_head_u(uint64_t value) {
  char text[rt::intTextMax];
  return *rt::formatUnsigned(value, text + sizeof text);
}
