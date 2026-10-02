// Standard output and input, and crash. Static storage and the stack
// only: the only libc symbols are write, read, _exit and getenv.
// PIN(runtime-quarantine) — see PINS.md

#include "internal.h"

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

// A line ends at '\n', as POSIX reads text, or at the "\r\n" that ends the
// lines of text written elsewhere; a '\r' anywhere else is the line's own.
extern "C" const idris_rt_str *idris_rt_io_get_line(void) {
  Line line;
  for (int32_t b = peek(); b >= 0; b = peek()) {
    ++inputPosition;
    if (b == '\n') {
      if (line.length > 0 && line.bytes[line.length - 1] == '\r')
        --line.length;
      break;
    }
    line.push(static_cast<char>(b));
  }
  return idris_rt_str_from_bytes(line.bytes, line.length);
}

// The bytes [offset, offset + count) of a byte array, or a crash.
char *byteRange(idris_rt_array *bytes, int64_t length, int64_t offset, int64_t count) {
  if (offset < 0 || count < 0 || offset > length || count > length - offset) {
    static constexpr char message[] = "idris-mlir: a byte range outside the buffer\n";
    idris_rt_crash(message, sizeof message - 1);
  }
  return reinterpret_cast<char *>(bytes + 1) + offset;
}

extern "C" int64_t idris_rt_io_write_bytes(int64_t handle, idris_rt_array *bytes, int64_t length,
                                           int64_t offset, int64_t count) {
  const char *p = byteRange(bytes, length, offset, count);
  auto n = static_cast<size_t>(count);
  if (handle == 1) {
    putBytes(p, n);
  } else if (handle == 2) {
    idris_rt_flush();
    rt::writeAll(2, p, n);
  } else {
    return 0;
  }
  return count;
}

extern "C" int64_t idris_rt_io_read_bytes(int64_t handle, idris_rt_array *bytes, int64_t length,
                                          int64_t offset, int64_t count) {
  char *p = byteRange(bytes, length, offset, count);
  if (handle != 0)
    return 0;
  int64_t got = 0;
  while (got < count && peek() >= 0) {
    size_t available = inputLength - inputPosition;
    auto wanted = static_cast<size_t>(count - got);
    size_t step = available < wanted ? available : wanted;
    volatile char *to = p + got;
    for (size_t i = 0; i < step; ++i)
      to[i] = input[inputPosition + i];
    inputPosition += step;
    got += static_cast<int64_t>(step);
  }
  return got;
}

extern "C" int64_t idris_rt_io_eof(int64_t handle) { return handle == 0 && inputEnded ? 1 : 0; }

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
