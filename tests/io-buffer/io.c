// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
/* Standard input and output through the runtime's buffers, whatever their
 * size: the run script links this program with the runtime's IO units built
 * for a buffer of the default size, of 4 bytes and of 7, and compares what
 * each prints.
 *
 *   io echo     each line of stdin, as idris_rt_io_get_line gives it,
 *               written back with a '\n', until the end of input
 *   io write    characters of every UTF-8 length, integers and doubles
 *               shown, and strings of 0 to 9 bytes in turn, then one of
 *               9000 bytes
 *   io crash    what write writes, then a crash at a site
 *
 * Every string it makes is released. It runs as a program does, on
 * idris_rt_start, whose end writes what the buffers hold. */
#include <string.h>

#include "idris_rt.h"
#include "program.h"

static void echo(void) {
  for (;;) {
    const idris_rt_str *line = idris_rt_io_get_line();
    /* An empty line is the end only once the input has ended: a line of
     * no bytes before that is a '\n' alone. */
    if (line->bytes == 0 && idris_rt_io_eof(0) == 1) {
      idris_rt_dec_cell((idris_rt_header *)&line->header);
      return;
    }
    idris_rt_io_put_str(line);
    idris_rt_io_put_char('\n');
    idris_rt_dec_cell((idris_rt_header *)&line->header);
  }
}

/* A character of each UTF-8 length, 1 to 4 bytes: idris_rt_io_put_char
 * encodes one in place, where 4 bytes fit. */
static const int32_t characters[] = {0x41, 0xE9, 0x65E5, 0x1F600};
enum { characterCount = sizeof characters / sizeof characters[0] };

/* A string the program made, written and released. */
static void putMade(const idris_rt_str *s) {
  idris_rt_io_put_str(s);
  idris_rt_dec_cell((idris_rt_header *)&s->header);
}

static void putString(const char *bytes, size_t n) { putMade(idris_rt_str_from_utf8(bytes, n)); }

static void writeEach(void) {
  static const char digits[] = "0123456789";
  /* Each character after a string of 0 to 9 bytes, each string after one of
   * 9, which a buffer of 4 or 7 bytes cannot hold, so it is empty again:
   * the character meets such a buffer at every offset, its end included. */
  for (size_t at = 0; at < 10; ++at) {
    for (int c = 0; c < characterCount; ++c) {
      putString(digits, 9);
      putString(digits, at);
      idris_rt_io_put_char(characters[c]);
      idris_rt_io_put_char('\n');
    }
  }
  static const double doubles[] = {0.0, -0.5, 1e21, 0.1, -1.5e-7};
  enum { doubleCount = sizeof doubles / sizeof doubles[0] };
  for (int round = 0; round < 10; ++round) {
    putMade(idris_rt_str_show_s((int64_t)round * 37 - 100));
    idris_rt_io_put_char(characters[round % characterCount]);
    putMade(idris_rt_str_show_f64(doubles[round % doubleCount]));
    idris_rt_io_put_char('\n');
  }
  /* Longer than the default buffer, so written past it at every size. */
  static char text[9000];
  for (size_t i = 0; i < sizeof text; ++i)
    text[i] = i % 80 == 79 ? '\n' : (char)('a' + i % 26);
  putString(text, sizeof text);
  idris_rt_io_put_char('\n');
}

/* A site's texts, laid out as idris_rt_text: the static texts of the
 * program the lowering writes, one per file and per function. */
static const struct {
  uint32_t length;
  char bytes[16];
} file = {8, "Main.idr"}, function = {9, "Main.main"};

static const char *mode = "";

static void body(void) {
  if (strcmp(mode, "echo") == 0) {
    echo();
  } else if (strcmp(mode, "write") == 0) {
    writeEach();
  } else {
    writeEach();
    /* The first cause of the specification's list, division by zero. */
    idris_rt_crash_at(0, (void *)&function, (void *)&file, 3, 7);
  }
}

/* A few frames of its own. */
IDRIS_RT_TEST_PROGRAM("io", 64 * 1024);

int main(int argc, char **argv) {
  mode = argc > 1 ? argv[1] : "";
  if (strcmp(mode, "echo") != 0 && strcmp(mode, "write") != 0 && strcmp(mode, "crash") != 0)
    return 2;
  idris_rt_test_start(body, argc, argv);
}
