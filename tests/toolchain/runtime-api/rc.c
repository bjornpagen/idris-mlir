/* Reference counting against cells built by hand as idr-lower lays them out:
 * counts, saturation, freeing (a structure of any depth, under the small
 * stack the run script gives, and arrays whose elements hold objects),
 * reuse, stack cells, and the live-cell count.
 * A failed check prints a line to standard error. The summary goes through
 * the runtime's output buffer, which idris_rt_main_return must flush; then
 * main returns as @main does.
 *
 *   rc          every check, then idris_rt_main_return
 *   rc leak     one cell left live, then idris_rt_main_return
 *   rc crash    one cell left live, then idris_rt_crash */
#include <stdio.h>
#include <string.h>
#include <sys/resource.h>

#include "idris_rt.h"

static int failures = 0, checks = 0;

static void check(int ok, const char *what) {
  ++checks;
  if (!ok) {
    fprintf(stderr, "FAIL %s\n", what);
    ++failures;
  }
}

static idris_rt_header *header(const void *o) { return (idris_rt_header *)o; }
static uint32_t count(const void *o) { return header(o)->count; }
static uint64_t live(void) { return idris_rt_live_cells(); }
static void **slot(void *cell, size_t offset) { return (void **)((char *)cell + offset); }
static void *word(int64_t small) { return (void *)(uintptr_t)(small << 1 | 1); }
static const idris_rt_str *text(const char *s) { return idris_rt_str_from_utf8(s, strlen(s)); }

static uint32_t box(uint32_t tag, uint32_t objs) {
  return idris_rt_info(tag, objs, IDRIS_RT_KIND_BOX);
}

/* A box of `objs` object slots and one plain word after them. */
static void *con(uint32_t tag, uint32_t objs, void *const *fields, int64_t plain) {
  void *cell = idris_rt_cell(8 + 8 * (size_t)objs + 8, box(tag, objs));
  for (uint32_t i = 0; i < objs; ++i)
    *slot(cell, 8 + 8 * (size_t)i) = fields[i];
  memcpy((char *)cell + 8 + 8 * (size_t)objs, &plain, sizeof plain);
  return cell;
}

/* A cons cell: the tail in its one object slot, then the head, a plain word. */
static void *cons(int64_t head, void *tail) { return con(1, 1, &tail, head); }

/* Static data: persistent, and everything it points to is persistent too. */
static struct {
  idris_rt_header header;
  void *tail;
  int64_t head;
} persistentCons = {{0, 1u | 1u << 16}, NULL, 7};
static idris_rt_header persistentNil = {0, 0};

static void noOps(void) {
  void *values[] = {NULL, word(21), word(-4), &persistentCons, &persistentNil};
  uint64_t before = live();
  for (size_t i = 0; i < sizeof values / sizeof values[0]; ++i) {
    void *o = values[i];
    idris_rt_inc(o);
    idris_rt_dec(o);
    idris_rt_dec(o);
    check(!idris_rt_is_unique(o), "NULL, a small big or static data is not exclusive");
    idris_rt_free_cell(o);
  }
  check(persistentCons.header.count == 0 && persistentNil.count == 0,
        "static data keeps count 0 through inc, dec and free_cell");
  check(persistentCons.header.info == (1u | 1u << 16) && persistentCons.head == 7,
        "static data is not written");
  check(live() == before, "NULL, small bigs and static data are not live cells");
}

static void balance(void) {
  uint64_t before = live();
  void *c = idris_rt_cell(16, box(7, 0));
  check(count(c) == 1 && header(c)->info == box(7, 0), "a new cell has count 1 and its info");
  check(live() == before + 1, "a new cell is live");
  check(idris_rt_is_unique(c), "a new cell is exclusive");
  for (int i = 0; i < 7; ++i)
    idris_rt_inc(c);
  check(count(c) == 8, "inc adds to the count");
  check(!idris_rt_is_unique(c), "a shared cell is not exclusive");
  for (int i = 0; i < 7; ++i)
    idris_rt_dec(c);
  check(count(c) == 1 && idris_rt_is_unique(c), "dec takes the count back to 1");
  check(live() == before + 1, "a cell stays live while it has a reference");
  idris_rt_dec(c);
  check(live() == before, "the last dec frees the cell");
}

static void saturation(void) {
  uint64_t before = live();
  void *c = idris_rt_cell(16, box(0, 0));
  header(c)->count = UINT32_MAX - 2;
  idris_rt_inc(c);
  check(count(c) == UINT32_MAX - 1, "inc below the saturation point counts");
  idris_rt_inc(c);
  check(count(c) == UINT32_MAX, "inc reaches the saturated count");
  idris_rt_inc(c);
  idris_rt_dec(c);
  idris_rt_dec(c);
  check(count(c) == UINT32_MAX, "a saturated count never changes");
  check(!idris_rt_is_unique(c), "a saturated cell is not exclusive");
  idris_rt_free_cell(c);
  check(live() == before + 1, "a saturated cell is never freed");
  /* A saturated cell leaks by design; this test takes it back. */
  header(c)->count = 1;
  idris_rt_dec(c);
  check(live() == before, "the cell taken back is freed");
}

static void lists(void) {
  uint64_t before = live();
  void *list = NULL;
  for (int64_t i = 0; i < 10000000; ++i)
    list = cons(i, list);
  check(live() == before + 10000000, "a list of 10^7 cells is 10^7 live cells");
  idris_rt_dec(list);
  check(live() == before, "one dec frees a list of 10^7 cells on a small stack");

  /* Linked through the first of two object slots, the second a small big:
   * freeing the last slot in a tail loop would not be enough. */
  list = &persistentNil;
  for (int64_t i = 0; i < 1000000; ++i) {
    void *fields[] = {list, word(i)};
    list = con(1, 2, fields, i);
  }
  idris_rt_dec(list);
  check(live() == before, "one dec frees a list linked through its first slot");

  /* A list ending in static data, and with a second owner halfway. */
  list = &persistentCons;
  void *middle = NULL;
  for (int64_t i = 0; i < 1000; ++i) {
    list = cons(i, list);
    if (i == 499)
      middle = list;
  }
  idris_rt_inc(middle);
  idris_rt_dec(list);
  check(live() == before + 500, "freeing stops at a cell with another owner");
  check(count(middle) == 1, "the shared cell loses one reference");
  idris_rt_dec(middle);
  check(live() == before, "its owner frees the rest");
  check(persistentCons.header.count == 0 && persistentCons.head == 7,
        "the static tail is not touched");
}

/* A complete binary tree of depth `depth`, as boxes of two object slots. */
static void *tree(int depth) {
  if (depth == 0)
    return NULL;
  void *fields[] = {tree(depth - 1), tree(depth - 1)};
  return con(2, 2, fields, depth);
}

static void trees(void) {
  uint64_t before = live();
  void *t = tree(20);
  check(live() == before + (1u << 20) - 1, "a tree of depth 20 is 2^20 - 1 live cells");
  idris_rt_dec(t);
  check(live() == before, "one dec frees a tree");

  /* Each node holds its child twice: two references in two slots. */
  void *dag = NULL;
  for (int i = 0; i < 100000; ++i) {
    idris_rt_inc(dag);
    void *fields[] = {dag, dag};
    dag = con(3, 2, fields, i);
  }
  check(live() == before + 100000, "a chain of shared nodes is one cell each");
  idris_rt_dec(dag);
  check(live() == before, "a node referenced from two slots is freed once, after both");
}

/* A thunk in the state of one of its labels, laid out as a box is: the
 * header (kind thunk, the state's tag), `objs` object captures, then one
 * plain capture. No code address: the force calls the label's function. */
static void *thunk(uint32_t state, uint32_t objs, void *const *captures) {
  void *cell = idris_rt_cell(8 + 8 * (size_t)objs + 8,
                             idris_rt_info(state, objs, IDRIS_RT_KIND_THUNK));
  for (uint32_t i = 0; i < objs; ++i)
    *slot(cell, 8 + 8 * (size_t)i) = captures[i];
  double plain = 2.5;
  memcpy((char *)cell + 8 + 8 * (size_t)objs, &plain, sizeof plain);
  return cell;
}

static void thunks(void) {
  uint64_t before = live();
  void *shared = cons(1, NULL);
  idris_rt_inc(shared);
  void *captures[] = {(void *)text("captured"), shared, cons(2, NULL), word(9)};
  void *t = thunk(5, 4, captures);
  check(live() == before + 4, "a thunk and what it captures are live");
  idris_rt_dec(t);
  check(live() == before + 1, "a thunk releases its captures as a box releases its fields");
  check(count(shared) == 1, "a shared capture loses one reference");
  idris_rt_dec(shared);

  void *chain = NULL;
  for (int i = 0; i < 1000000; ++i)
    chain = thunk(6, 1, &chain);
  idris_rt_dec(chain);
  check(live() == before, "one dec frees a chain of 10^6 thunks");
}

/* An array of five elements, each a box in its one object slot and a plain
 * word after it, so 16 bytes: the array's tag is that size and its objs the
 * one slot. Element i holds cons(i), but element 2 holds `shared`. */
static idris_rt_array *boxes(void *shared) {
  idris_rt_array *a = idris_rt_array_new(5, idris_rt_info(16, 1, IDRIS_RT_KIND_ARRAY));
  for (int64_t i = 0; i < 5; ++i) {
    char *element = (char *)a + sizeof(idris_rt_array) + 16 * (size_t)i;
    *(void **)element = i == 2 ? shared : cons(i, NULL);
    memcpy(element + 8, &i, sizeof i);
  }
  return a;
}

/* Freeing an array releases each element's object slots, read at the
 * element size its tag gives, whether the array dies alone or in the
 * worklist of a cell that held it. */
static void arrays(void) {
  uint64_t before = live();
  void *shared = cons(9, NULL);
  idris_rt_inc(shared);
  idris_rt_array *a = boxes(shared);
  check(live() == before + 6, "an array and the five boxes its elements hold are live");
  idris_rt_dec(a);
  check(live() == before + 1 && count(shared) == 1,
        "an array freed directly releases each element's box, a shared one once");
  idris_rt_dec(shared);
  check(live() == before, "nothing of the array is left");

  shared = cons(9, NULL);
  idris_rt_inc(shared);
  void *held = boxes(shared);
  void *holder = con(7, 1, &held, 0);
  check(live() == before + 7, "a box holding an array, the array and its boxes are live");
  idris_rt_dec(holder);
  check(live() == before + 1 && count(shared) == 1,
        "an array freed inside a dying box releases each element's box, a shared one once");
  idris_rt_dec(shared);
  check(live() == before, "nothing of the box or its array is left");
}

static void stringsAndBignums(void) {
  uint64_t before = live();
  const idris_rt_str *a = text("héllo"), *b = text(" wörld"), *ascii = text("ascii");
  const idris_rt_str *empty = text("");
  check(count(a) == 1 && header(a)->info == idris_rt_info(0, 0, IDRIS_RT_KIND_STRING),
        "a new string is a cell of kind string, tag 0 when not ASCII");
  check(header(ascii)->info == idris_rt_info(1, 0, IDRIS_RT_KIND_STRING),
        "an ASCII string has tag 1");
  check(count(empty) == 0 && live() == before + 3, "the empty string is persistent");
  const idris_rt_str *ab = idris_rt_str_append(a, b);
  check(count(ab) == 1 && live() == before + 4, "append returns a new string");
  const idris_rt_str *ae = idris_rt_str_append(a, empty), *ea = idris_rt_str_append(empty, a);
  check(ae == a && ea == a && count(a) == 3,
        "appending the empty string returns the other one, with a reference for the caller");
  const idris_rt_str *r = idris_rt_str_reverse(empty);
  check(r == empty && count(empty) == 0, "reversing the empty string returns it, still persistent");
  const idris_rt_str *whole = idris_rt_str_drop_bytes(a, 0);
  check(whole == a && count(a) == 4,
        "dropping no bytes returns the string, with a reference for the caller");
  const idris_rt_str *none = idris_rt_str_drop_bytes(a, 100);
  check(none == empty && count(empty) == 0,
        "dropping every byte returns the persistent empty string");
  /* Offset 2 is inside the two bytes of the e with an acute accent, so the
   * rest starts with it. */
  const idris_rt_str *rest = idris_rt_str_drop_bytes(a, 2);
  check(rest != a && count(rest) == 1 && rest->bytes == 5 && rest->scalars == 4 &&
            memcmp(idris_rt_str_bytes(rest), "\xC3\xA9llo", 5) == 0 &&
            header(rest)->info == header(a)->info,
        "dropping some bytes returns a new string with the flag of its source");
  const idris_rt_str *strings[] = {ae, ea, ab, a, b, ascii, empty, r, whole, none, rest};
  for (size_t i = 0; i < sizeof strings / sizeof strings[0]; ++i)
    idris_rt_dec((void *)strings[i]);
  check(live() == before, "strings are freed by dec");

  const idris_rt_str *digits = text("123456789012345678901234567890");
  idris_rt_big x = idris_rt_big_from_str(digits);
  idris_rt_dec((void *)digits);
  check((x & 1) == 0 && count((void *)(uintptr_t)x) == 1 &&
            header((void *)(uintptr_t)x)->info == idris_rt_info(0, 0, IDRIS_RT_KIND_BIGNUM),
        "a big outside the small range is a cell of kind bignum");
  idris_rt_big y = idris_rt_big_mul(x, x);
  idris_rt_big zero = idris_rt_big_sub(y, y);
  check(zero == 1, "a result in the small range is a small word, not a cell");
  const idris_rt_str *shown = idris_rt_big_show(y);
  check(count(shown) == 1, "show returns a new string");
  idris_rt_dec((void *)shown);
  idris_rt_big_release(zero);
  idris_rt_big_release(y);
  check(live() == before + 1, "bignums are freed by dec");

  /* A box that owns a bignum, a string and a small big. */
  void *fields[] = {(void *)(uintptr_t)x, (void *)text("owned"), word(-3)};
  idris_rt_dec(con(4, 3, fields, 0));
  check(live() == before, "a box releases the bignum and the string it owns");
}

/* What idr.take and idr.reuse do with a cell whose box dies: when it is
 * exclusive its fields move out with their references and its memory is
 * rewritten in place, or freed alone when nothing reuses it. */
static void tokens(void) {
  uint64_t before = live();
  void *unique = cons(1, NULL), *shared = cons(2, NULL);
  idris_rt_inc(shared);
  void *fields[] = {unique, shared};
  void *cell = con(2, 2, fields, 0);
  check(idris_rt_is_unique(cell), "a new cell is exclusive");
  /* The fields move out, and the moved references are dropped. */
  idris_rt_dec(unique);
  idris_rt_dec(shared);
  check(live() == before + 2 && count(shared) == 1, "the moved fields keep their references");
  /* Reuse: a cell of the same size with a new header and fields. */
  header(cell)->info = box(9, 1);
  *slot(cell, 8) = shared;
  *slot(cell, 16) = NULL;
  idris_rt_dec(cell);
  check(live() == before, "a reused cell is an ordinary cell");

  void *other[] = {cons(3, NULL), NULL};
  cell = con(2, 2, other, 0);
  idris_rt_dec(other[0]);
  idris_rt_free_cell(cell);
  check(live() == before, "free_cell frees a cell whose fields moved out");

  void *twice = cons(4, NULL);
  idris_rt_inc(twice);
  check(!idris_rt_is_unique(twice), "a cell with two references is not exclusive");
  idris_rt_dec(twice);
  idris_rt_dec(twice);
  check(live() == before, "a shared cell is freed with its last reference");
}

static void stackCells(void) {
  uint64_t before = live();
  struct {
    idris_rt_header header;
    void *slots[2];
    int64_t plain;
  } frame = {{1, box(4, 2) | IDRIS_RT_STACK_CELL}, {cons(1, NULL), cons(2, NULL)}, 99};
  void *shared = frame.slots[1];
  idris_rt_inc(shared);
  check(live() == before + 2, "a stack cell is not a live cell");
  check(!idris_rt_is_unique(&frame), "a stack cell is never exclusive");
  idris_rt_inc(&frame);
  idris_rt_dec(&frame);
  check(frame.header.count == 1 && !idris_rt_is_unique(&frame),
        "a stack cell at count 1 is not exclusive either");
  idris_rt_dec(&frame);
  check(frame.header.count == 0 && frame.plain == 99,
        "a stack cell at count 0 is inert, and its memory is its frame's");
  check(live() == before + 1 && count(shared) == 1, "a dead stack cell released its slots");
  idris_rt_dec(&frame);
  idris_rt_free_cell(&frame);
  idris_rt_dec(shared);
  check(live() == before, "the rest is freed by its owner");

  struct {
    idris_rt_header header;
    void *slots[1];
    int64_t plain;
  } inner = {{1, box(5, 1) | IDRIS_RT_STACK_CELL}, {cons(3, NULL)}, 42};
  idris_rt_free_cell(&inner);
  check(inner.header.count == 1 && live() == before + 1, "free_cell leaves a stack cell alone");
  /* Held in a heap cell's slot, which idr-stack never builds, a stack cell
   * still keeps its memory when it dies. */
  void *holder = cons(0, &inner);
  idris_rt_dec(holder);
  check(inner.header.count == 0 && inner.plain == 42 && live() == before,
        "a stack cell that dies in a worklist releases its slots and keeps its memory");
}

static void report(void) {
  char line[64];
  int n = snprintf(line, sizeof line, "rc: %d of %d checks as idris_rt.h defines them\n",
                   checks - failures, checks);
  const idris_rt_str *s = idris_rt_str_from_utf8(line, (size_t)n);
  idris_rt_io_put_str(s);
  idris_rt_dec((void *)s);
}

int main(int argc, char **argv) {
  const char *mode = argc > 1 ? argv[1] : "";
  if (strcmp(mode, "leak") == 0) {
    idris_rt_cell(16, box(0, 0));
    idris_rt_main_return();
    return 0;
  }
  if (strcmp(mode, "crash") == 0) {
    idris_rt_cell(16, box(0, 0));
    static const char message[] = "crashed\n";
    idris_rt_crash(message, sizeof message - 1);
  }
  struct rlimit stack;
  if (getrlimit(RLIMIT_STACK, &stack) == 0 && stack.rlim_cur != RLIM_INFINITY)
    printf("stack: %llu KiB\n", (unsigned long long)stack.rlim_cur / 1024);
  else
    printf("stack: unlimited\n");
  fflush(stdout);
  noOps();
  balance();
  saturation();
  lists();
  trees();
  thunks();
  arrays();
  stringsAndBignums();
  tokens();
  stackCells();
  check(live() == 0, "nothing is live at the end");
  report();
  idris_rt_main_return();
  return failures == 0 ? 0 : 1;
}
