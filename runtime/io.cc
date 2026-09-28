// Standard output and input, exit and crash (LOW-IO-1..4, LOW-CRASH-1;
// SEM-IO-2..7, SEM-PROG-2, SEM-CRASH-1). Static storage and the stack only:
// the only libc symbols are write, read and _exit (LOW-EXT-1).
// PIN(runtime-quarantine) — see PINS.md

#include "internal.h"

#include <unistd.h>

namespace {

constexpr size_t bufferSize = 4096;

// Written through a volatile pointer, so that LLVM makes no memcpy of the
// copy loop (LOW-EXT-1).
char output[bufferSize];
size_t outputLength = 0;

char input[bufferSize];
size_t inputPosition = 0;
size_t inputLength = 0;

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
// before the program blocks reading (SEM-IO-4).
int32_t peek() {
  if (inputPosition >= inputLength) {
    idris_rt_flush();
    ssize_t got = read(0, input, bufferSize);
    inputLength = got > 0 ? static_cast<size_t>(got) : 0;
    inputPosition = 0;
  }
  if (inputPosition < inputLength)
    return static_cast<unsigned char>(input[inputPosition]);
  return -1;
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

extern "C" void idris_rt_put_str(const idris_rt_str *s) {
  putBytes(idris_rt_str_bytes(s), s->bytes);
}

extern "C" void idris_rt_put_char(int32_t c) {
  char bytes[4];
  putBytes(bytes, rt::encodeUtf8(c, bytes));
}

extern "C" void idris_rt_put_int_s(int64_t value) {
  char text[rt::intTextMax];
  char *end = text + sizeof text;
  char *start = rt::formatSigned(value, end);
  putBytes(start, static_cast<size_t>(end - start));
}

extern "C" void idris_rt_put_int_u(uint64_t value) {
  char text[rt::intTextMax];
  char *end = text + sizeof text;
  char *start = rt::formatUnsigned(value, end);
  putBytes(start, static_cast<size_t>(end - start));
}

extern "C" void idris_rt_put_double(double value) {
  char text[rt::doubleTextMax];
  putBytes(text, rt::formatDouble(value, text));
}

extern "C" int32_t idris_rt_get_byte(void) {
  int32_t b = peek();
  if (b < 0)
    return 255;
  ++inputPosition;
  return b;
}

// The first byte decides the length and the range of the second byte
// (Unicode's table of well-formed byte sequences); a byte outside it ends a
// maximal invalid subsequence, which is not consumed.
extern "C" int32_t idris_rt_get_char(void) {
  int32_t b0 = peek();
  if (b0 < 0)
    return 0;
  ++inputPosition;
  if (b0 < 0x80)
    return b0;
  int32_t n;
  int32_t value;
  if (b0 >= 0xC2 && b0 <= 0xDF) {
    n = 2;
    value = b0 & 0x1F;
  } else if (b0 >= 0xE0 && b0 <= 0xEF) {
    n = 3;
    value = b0 & 0x0F;
  } else if (b0 >= 0xF0 && b0 <= 0xF4) {
    n = 4;
    value = b0 & 0x07;
  } else {
    return 0xFFFD;
  }
  int32_t low = b0 == 0xE0 ? 0xA0 : b0 == 0xF0 ? 0x90 : 0x80;
  int32_t high = b0 == 0xED ? 0x9F : b0 == 0xF4 ? 0x8F : 0xBF;
  for (int32_t k = 1; k < n; ++k) {
    int32_t b = peek();
    if (b < low || b > high)
      return 0xFFFD;
    ++inputPosition;
    value = (value << 6) | (b & 0x3F);
    low = 0x80;
    high = 0xBF;
  }
  return value;
}

extern "C" void idris_rt_exit(int64_t code) {
  idris_rt_flush();
  _exit(static_cast<int>(code & 0xFF));
}

extern "C" void idris_rt_crash(const char *msg, size_t len) {
  idris_rt_flush();
  rt::writeAll(2, msg, len);
  _exit(1);
}

extern "C" int32_t idris_rt_int_head_s(int64_t value) {
  char text[rt::intTextMax];
  return *rt::formatSigned(value, text + sizeof text);
}

extern "C" int32_t idris_rt_int_head_u(uint64_t value) {
  char text[rt::intTextMax];
  return *rt::formatUnsigned(value, text + sizeof text);
}
