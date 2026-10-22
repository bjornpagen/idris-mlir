// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
/* Standard input and output through the runtime's buffers, of the size the
 * runtime ships, which the run script gives as SIZE: the target's page.
 *
 *   io echo          each line of stdin, as idris_rt_io_get_line gives it,
 *                    written back with a '\n', until the end of input
 *   io write SIZE    texts and characters of every UTF-8 length, each
 *                    character meeting the buffer's end at every offset
 *                    from 0 to 9, then a text longer than two buffers
 *   io direct SIZE   the same pieces, each written straight to the
 *                    descriptor through no buffer: what write must print
 *   io crash SIZE    what write writes, then a crash at a site
 *
 * Every string it makes is released. It runs as a program does, on
 * idris_rt_start, whose end writes what the buffers hold. */
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

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

/* How a piece reaches standard output: through the runtime's buffer, or
 * straight to the descriptor, the oracle's way, which no buffer's size or
 * boundary can change. */
enum Through { Buffered, Direct };
static enum Through through = Buffered;

static void direct(const char *bytes, size_t n) {
  while (n > 0) {
    ssize_t wrote = write(1, bytes, n);
    if (wrote <= 0)
      exit(3);
    bytes += wrote;
    n -= (size_t)wrote;
  }
}

/* A character of each UTF-8 length, 1 to 4 bytes, with its encoding, the
 * oracle's own: idris_rt_io_put_char encodes one in place. */
static const struct {
  int32_t scalar;
  const char *utf8;
} characters[] = {
    {0x41, "A"}, {0xE9, "\xC3\xA9"}, {0x65E5, "\xE6\x97\xA5"}, {0x1F600, "\xF0\x9F\x98\x80"}};
enum { characterCount = sizeof characters / sizeof characters[0] };

static void putText(const char *bytes, size_t n) {
  if (through == Direct) {
    direct(bytes, n);
    return;
  }
  const idris_rt_str *s = idris_rt_str_from_utf8(bytes, n);
  idris_rt_io_put_str(s);
  idris_rt_dec_cell((idris_rt_header *)&s->header);
}

static void putCharacter(int32_t scalar, const char *utf8) {
  if (through == Direct)
    direct(utf8, strlen(utf8));
  else
    idris_rt_io_put_char(scalar);
}

static size_t size = 0;

static void writeEach(void) {
  /* Longer than two buffers, so written past one at every size. */
  size_t longest = 2 * size + 7;
  char *text = malloc(longest);
  if (!text)
    exit(3);
  for (size_t i = 0; i < longest; ++i)
    text[i] = i % 80 == 79 ? '\n' : (char)('a' + i % 26);
  /* Each character after a text of a buffer's size, which leaves the
   * buffer full, so the next text starts it again, and that text is `at`
   * bytes short of the buffer: the character meets its end at every offset
   * from 0 to 9. */
  for (size_t at = 0; at < 10; ++at) {
    for (int c = 0; c < characterCount; ++c) {
      putText(text, size);
      putText(text, size - at);
      putCharacter(characters[c].scalar, characters[c].utf8);
      putCharacter('\n', "\n");
    }
  }
  putText(text, longest);
  putCharacter('\n', "\n");
  free(text);
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
  } else if (strcmp(mode, "direct") == 0) {
    through = Direct;
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
  if (strcmp(mode, "echo") != 0) {
    if (strcmp(mode, "write") != 0 && strcmp(mode, "direct") != 0 && strcmp(mode, "crash") != 0)
      return 2;
    /* A buffer holds a character's longest UTF-8 and the ten offsets. */
    char *end = NULL;
    size = argc > 2 ? (size_t)strtoull(argv[2], &end, 10) : 0;
    if (!end || *end != '\0' || size < 10)
      return 2;
  }
  idris_rt_test_start(body, argc, argv);
}
