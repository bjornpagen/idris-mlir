/* reverse-complement on one core, as Main.idr here: the whole input read,
   each record's sequence reversed and complemented, 60 characters to a
   line. */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static char comp[256];

static void put_sequence(char *seq, long len) {
  for (long i = 0, j = len - 1; i < j; i++, j--) { char t = seq[i]; seq[i] = seq[j]; seq[j] = t; }
  for (long i = 0; i < len; i += 60) {
    long m = len - i < 60 ? len - i : 60;
    fwrite(seq + i, 1, m, stdout);
    putchar('\n');
  }
}

int main(void) {
  for (int c = 0; c < 256; c++) comp[c] = (char)c;
  const char *from = "ACGTUMRWSYKVHDBNacgtumrwsykvhdbn", *to = "TGCAAKYWSRMBDHVNTGCAAKYWSRMBDHVN";
  for (int i = 0; from[i]; i++) comp[(unsigned char)from[i]] = to[i];
  size_t cap = 1 << 20, len = 0;
  char *buf = malloc(cap);
  size_t got;
  while ((got = fread(buf + len, 1, cap - len, stdin)) > 0) {
    len += got;
    if (len == cap) { cap *= 2; buf = realloc(buf, cap); }
  }
  char *seq = malloc(len + 1);
  long slen = 0;
  size_t i = 0;
  while (i < len) {
    if (buf[i] == '>') {
      if (slen) { put_sequence(seq, slen); slen = 0; }
      size_t j = i;
      while (j < len && buf[j] != '\n') j++;
      fwrite(buf + i, 1, j - i, stdout);
      putchar('\n');
      i = j + 1;
    } else if (buf[i] == '\n') {
      i++;
    } else {
      seq[slen++] = comp[(unsigned char)buf[i++]];
    }
  }
  if (slen) put_sequence(seq, slen);
  return 0;
}
