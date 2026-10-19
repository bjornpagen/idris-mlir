// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
/* chameneos-redux (the Benchmarks Game), as Main.idr here. The game
   specifies one thread per creature; threads are outside the compiler this
   compares against, so this is the same workload under the same
   deterministic cooperative scheduler, without threads: the creatures that
   can run wait in a run queue, the one at its head goes to the meeting
   place, and a pair that has met joins the back of the queue, the creature
   that was waiting first. Its output is byte for byte Main.idr's. */
#include <stdio.h>

enum colour { BLUE, RED, YELLOW };

static const char *const colour_name[] = { "blue", "red", "yellow" };

static enum colour complement(enum colour a, enum colour b) {
  static const enum colour table[3][3] = {
    { BLUE, YELLOW, RED },
    { YELLOW, RED, BLUE },
    { RED, BLUE, YELLOW },
  };
  return table[a][b];
}

typedef struct {
  enum colour colour;
  long meetings, self_meetings;
} creature;

/* The game's spelling of a number: each decimal digit as a word, each
   after a space. */
static void spell(long n) {
  static const char *const digit[] = {
    "zero", "one", "two", "three", "four", "five", "six", "seven", "eight", "nine",
  };
  char s[32];
  int len = snprintf(s, sizeof s, "%ld", n);
  for (int i = 0; i < len; i++) printf(" %s", digit[s[i] - '0']);
}

#define MAX_CREATURES 10

static void game(long n, const enum colour *colours, int count) {
  creature cs[MAX_CREATURES];
  /* The run queue, a ring of creature indices; it never holds more than
     every creature. */
  int queue[MAX_CREATURES + 1];
  int head = 0, tail = 0, waiter = -1;
  for (int i = 0; i < count; i++) {
    printf(" %s", colour_name[colours[i]]);
    cs[i] = (creature){ colours[i], 0, 0 };
    queue[tail++] = i;
  }
  printf("\n");
  /* The creature at the head arrives: once the place has closed every
     creature fades; with nobody waiting it waits; otherwise the two meet. */
  while (n > 0) {
    int c = queue[head];
    head = (head + 1) % (MAX_CREATURES + 1);
    if (waiter < 0) {
      waiter = c;
      continue;
    }
    int w = waiter;
    enum colour k = complement(cs[c].colour, cs[w].colour);
    long same = c == w;
    cs[w].colour = cs[c].colour = k;
    cs[w].meetings++;
    cs[c].meetings++;
    cs[w].self_meetings += same;
    cs[c].self_meetings += same;
    queue[tail] = w;
    tail = (tail + 1) % (MAX_CREATURES + 1);
    queue[tail] = c;
    tail = (tail + 1) % (MAX_CREATURES + 1);
    waiter = -1;
    n--;
  }
  long total = 0;
  for (int i = 0; i < count; i++) {
    printf("%ld", cs[i].meetings);
    spell(cs[i].self_meetings);
    printf("\n");
    total += cs[i].meetings;
  }
  spell(total);
  printf("\n\n");
}

static long read_int(void) {
  long n = 0;
  int c;
  while ((c = getchar()) >= '0' && c <= '9') n = n * 10 + (c - '0');
  return n;
}

int main(void) {
  long n = read_int();
  for (int a = BLUE; a <= YELLOW; a++)
    for (int b = BLUE; b <= YELLOW; b++)
      printf("%s + %s -> %s\n", colour_name[a], colour_name[b], colour_name[complement(a, b)]);
  printf("\n");
  static const enum colour three[] = { BLUE, RED, YELLOW };
  static const enum colour ten[] = { BLUE, RED, YELLOW, RED, YELLOW, BLUE, RED, YELLOW, RED, BLUE };
  game(n, three, 3);
  game(n, ten, 10);
  return 0;
}
