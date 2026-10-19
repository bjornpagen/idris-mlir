// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
/* meteor-contest on one core, as Main.idr here: every way to fill the
   50-cell hexagonal board with the ten pieces, counted up to the limit read
   from stdin, and the smallest and largest solution, read as 50 digits in
   cell order, printed as the game's pretty board.

   A cell is row * 5 + column; odd rows sit half a cell to the right. A
   piece is the path from one of its cells through the other four, in the
   twelve directions of the game's C entry (even ones to a neighbour, odd
   ones to the cell two steps away between two neighbours). Its placements
   are every start cell under every rotation (direction + 2) and flip
   (12 - direction), each a 50-bit mask, kept under its lowest cell. No
   piece has a symmetry, so no two of a piece's placements are alike, and a
   solution is found once. The search fills the lowest empty cell, found by
   stepping on from the last one filled, with each unused piece placed
   there, in the order of the pieces and then of the placements, and
   backtracks. */
#include <stdint.h>
#include <stdio.h>
#include <string.h>

static long read_int(void) {
  long n = 0;
  int c;
  while ((c = getchar()) >= '0' && c <= '9') n = n * 10 + (c - '0');
  return n;
}

static const int piece_def[10][4] = {
  {0, 0, 0, 2},  {2, 0, 10, 0}, {0, 0, 2, 4}, {0, 0, 4, 2},  {2, 0, 10, 3},
  {0, 0, 4, 0},  {0, 2, 2, 10}, {0, 2, 2, 6}, {0, 2, 0, 0},  {0, 0, 0, 4},
};

/* The twelve directions as steps of axial coordinates (q, r), where a cell
   in row r and column c has q = c - r / 2. */
static const int dq[12] = {1, 1, 0, -1, -1, -2, -1, -1, 0, 1, 1, 2};
static const int dr[12] = {0, 1, 1, 2, 1, 1, 0, -1, -1, -2, -1, -1};

/* The placements whose lowest cell is cell: count[cell] of them, each
   piece[cell][k] at mask[cell][k], in the order they were made (at most
   one per piece and orientation). */
static int count[50];
static int piece[50][120];
static uint64_t mask[50][120];

static uint64_t full;
static long limit, found;
static uint64_t chosen[10];
static char best[50], worst[50];

/* Piece p from start in an orientation: its mask and lowest cell, or 0 when
   a cell is off the board. */
static int place(int p, int start, int orient, int flip, uint64_t *covered, int *low) {
  int q = start % 5 - start / 10, r = start / 5;
  uint64_t m = 1ull << start;
  int lo = start;
  for (int k = 0; k < 4; k++) {
    int d = piece_def[p][k];
    if (flip) d = (12 - d) % 12;
    d = (d + 2 * orient) % 12;
    q += dq[d];
    r += dr[d];
    int c = q + r / 2;
    if (r < 0 || r >= 10 || c < 0 || c >= 5) return 0;
    int cell = r * 5 + c;
    m |= 1ull << cell;
    if (cell < lo) lo = cell;
  }
  *covered = m;
  *low = lo;
  return 1;
}

static void record(void) {
  char s[50];
  for (int p = 0; p < 10; p++)
    for (int i = 0; i < 50; i++)
      if (chosen[p] >> i & 1) s[i] = (char)p;
  if (found == 0 || memcmp(s, best, 50) < 0) memcpy(best, s, 50);
  if (found == 0 || memcmp(s, worst, 50) > 0) memcpy(worst, s, 50);
  found++;
}

static void solve(uint64_t board, int used, int cell) {
  if (board == full) {
    record();
    return;
  }
  while (board >> cell & 1) cell++;
  for (int k = 0; k < count[cell] && found < limit; k++) {
    int p = piece[cell][k];
    uint64_t m = mask[cell][k];
    if (used >> p & 1 || m & board) continue;
    chosen[p] = m;
    solve(board | m, used | 1 << p, cell);
  }
}

static void pretty(const char *b) {
  for (int i = 0; i < 50; i += 10)
    printf("%c %c %c %c %c \n %c %c %c %c %c \n", b[i] + '0', b[i + 1] + '0', b[i + 2] + '0',
           b[i + 3] + '0', b[i + 4] + '0', b[i + 5] + '0', b[i + 6] + '0', b[i + 7] + '0',
           b[i + 8] + '0', b[i + 9] + '0');
  printf("\n");
}

int main(void) {
  limit = read_int();
  full = (1ull << 50) - 1;
  for (int p = 0; p < 10; p++)
    for (int flip = 0; flip < 2; flip++)
      for (int orient = 0; orient < 6; orient++)
        for (int start = 0; start < 50; start++) {
          uint64_t m;
          int lo;
          if (!place(p, start, orient, flip, &m, &lo)) continue;
          piece[lo][count[lo]] = p;
          mask[lo][count[lo]++] = m;
        }
  solve(0, 0, 0);
  printf("%ld solutions found\n\n", found);
  if (found > 0) {
    pretty(best);
    pretty(worst);
  }
  return 0;
}
