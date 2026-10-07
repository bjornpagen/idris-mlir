/* regex-redux on one core, the same patterns and the same order as
   Main.idr here. The game's C entries link PCRE or PCRE2; this uses POSIX
   regex, which macOS libc and musl both have, so the suite pins no second
   regex library. POSIX is the slower matcher. */
#include <regex.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static char *read_all(size_t *n) {
  size_t cap = 1 << 20, len = 0;
  char *buf = malloc(cap);
  size_t got;
  while ((got = fread(buf + len, 1, cap - len - 1, stdin)) > 0) {
    len += got;
    if (len + 1 == cap) {
      cap *= 2;
      buf = realloc(buf, cap);
    }
  }
  buf[len] = 0;
  *n = len;
  return buf;
}

static void compile(regex_t *re, const char *pat) {
  /* REG_NEWLINE: a period does not match a newline. Without it POSIX treats
     newline as an ordinary character, so one header would eat the file. */
  int err = regcomp(re, pat, REG_EXTENDED | REG_NEWLINE);
  if (err) {
    char msg[256];
    regerror(err, re, msg, sizeof msg);
    fprintf(stderr, "regex: %s\n", msg);
    exit(1);
  }
}

/* Non-overlapping matches, each search starting where the last match ended,
   as the Idris matcher continues on the unmatched tail. */
static long count_matches(const char *pat, const char *s) {
  regex_t re;
  compile(&re, pat);
  long n = 0;
  const char *p = s;
  regmatch_t m;
  while (*p && regexec(&re, p, 1, &m, 0) == 0) {
    n++;
    if (m.rm_eo <= 0) p++;
    else p += m.rm_eo;
  }
  regfree(&re);
  return n;
}

static char *replace_all(const char *pat, const char *rep, const char *s, size_t *n) {
  regex_t re;
  compile(&re, pat);
  size_t rlen = strlen(rep), cap = *n + 1, len = 0;
  char *out = malloc(cap);
  const char *p = s;
  regmatch_t m;
  while (*p && regexec(&re, p, 1, &m, 0) == 0) {
    size_t before = (size_t)m.rm_so, taken = (size_t)(m.rm_eo > 0 ? m.rm_eo : 1);
    size_t need = len + before + rlen + 1;
    while (cap < need) cap *= 2;
    out = realloc(out, cap);
    memcpy(out + len, p, before);
    len += before;
    memcpy(out + len, rep, rlen);
    len += rlen;
    p += taken;
  }
  size_t rest = strlen(p);
  while (cap < len + rest + 1) cap *= 2;
  out = realloc(out, cap);
  memcpy(out + len, p, rest);
  len += rest;
  out[len] = 0;
  *n = len;
  regfree(&re);
  return out;
}

int main(void) {
  size_t ilen = 0;
  char *input = read_all(&ilen);
  /* A real newline in the pattern, not a regex escape: POSIX does not
     define \n inside an expression, and both libcs match the byte. */
  static const char strip[] = ">.*\n|\n";
  static const char *variants[] = {
      "agggtaaa|tttaccct",
      "[cgt]gggtaaa|tttaccc[acg]",
      "a[act]ggtaaa|tttacc[agt]t",
      "ag[act]gtaaa|tttac[agt]ct",
      "agg[act]taaa|ttta[agt]cct",
      "aggg[acg]aaa|ttt[cgt]ccct",
      "agggt[cgt]aa|tt[acg]accct",
      "agggta[cgt]a|t[acg]taccct",
      "agggtaa[cgt]|[acg]ttaccct",
  };
  /* Literal bars as a class: \| is not a portable POSIX escape. */
  static const char *pats[] = {"tHa[Nt]", "aND|caN|Ha[DS]|WaS", "a[NSt]|BY", "<[^>]*>",
                               "[|][^|][^|]*[|]"};
  static const char *reps[] = {"<4>", "<3>", "<2>", "|", "-"};
  size_t slen = ilen;
  char *seq = replace_all(strip, "", input, &slen);
  for (int i = 0; i < 9; i++) printf("%s %ld\n", variants[i], count_matches(variants[i], seq));
  char *cur = seq;
  size_t clen = slen;
  for (int i = 0; i < 5; i++) {
    char *next = replace_all(pats[i], reps[i], cur, &clen);
    if (cur != seq) free(cur);
    cur = next;
  }
  printf("\n%zu\n%zu\n%zu\n", ilen, slen, clen);
  free(input);
  free(seq);
  if (cur != seq) free(cur);
  return 0;
}
