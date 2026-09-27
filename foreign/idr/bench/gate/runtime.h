// The memory gate's runtime prototype (docs/plan.md 4.3, 4.4, 5.6, 7.4): the
// C ABI that the hand-lowered programs in bench/gate/lowered call. How to
// build and run it: bench/gate/README.md.
//
// A heap cell is an 8-byte header followed by its fields, pointer fields
// first:
//
//   byte 0-3  count: > 0 owned by one core (plain arithmetic); < 0 shared
//             (atomic, |count| references); 0 persistent (never counted);
//             INT32_MAX sticks (the cell is never freed)
//   byte 4    kind: IDR_KIND_CTOR (the only kind the gate uses)
//   byte 5    constructor tag
//   byte 6    number of pointer fields
//   byte 7    size of the cell in 8-byte words, header included
//
// A pointer field holds a cell or an immediate: a nullary constructor is
// (tag << 1) | 1, so an immediate has its low bit set.
//
// While a dying cell waits on the free list, its bytes 0-5 hold the link to
// the next one (a 48-bit pointer, as in Lean's lean_del_core) and bytes 6-7,
// all that freeing needs, stay intact.
#pragma once

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

enum { IDR_KIND_CTOR = 0, IDR_KIND_STR = 1 };

typedef struct IdrCell {
  int32_t rc;
  uint8_t kind;
  uint8_t tag;
  uint8_t nptr;
  uint8_t nwords;
} IdrCell;

// One entry per size class (snmalloc's alloc<S>, with 8-byte steps: plan
// 5.6). The cell comes back uninitialized.
void *idr_alloc_16(void);
void *idr_alloc_24(void);
void *idr_alloc_32(void);
void *idr_alloc_40(void);
void *idr_alloc_48(void);
void *idr_alloc_56(void);
void *idr_alloc_64(void);
void idr_free_16(void *cell);
void idr_free_24(void *cell);
void idr_free_32(void *cell);
void idr_free_40(void *cell);
void idr_free_48(void *cell);
void idr_free_56(void *cell);
void idr_free_64(void *cell);

// The count operations' slow paths. The lowering inlines the fast paths:
// increment when 0 < count < INT32_MAX, decrement when 1 < count < INT32_MAX.
// idr_inc_cold handles shared (atomic), persistent and stuck counts;
// idr_dec_cold also frees a cell whose count reaches zero.
void idr_inc_cold(IdrCell *cell);
void idr_dec_cold(IdrCell *cell);

// Frees a cell whose last reference the caller holds, and everything that
// dies with it, iteratively through the free list.
void idr_free_cell(IdrCell *cell);

// Move-or-mark (plan 4.3, 7.4): called on a value, which may be an
// immediate, before its reference crosses to another core. One walk moves
// each cell whose count is 1 (it stays non-atomic, now the receiver's) and
// marks shared each cell with a higher count, with everything it reaches.
void idr_send(void *value);

// Strings are cells of kind IDR_KIND_STR with no pointer fields: the header,
// the length in bytes, then the UTF-8 bytes. The gate's only strings are
// literals, persistent in read-only data. Equality of two strings:
int32_t idr_str_eq(const void *a, const void *b);

// Input and output.
int64_t idr_read_int(void);
void idr_put_int(int64_t value);
void idr_put_str(const char *bytes, int64_t length);
void idr_put_char(int32_t scalar);

// Thread per core (experiment 3). Cores are numbered from 0; the program's
// main runs pinned to core 0.
int64_t idr_cores(void);

// Runs body(env, i) for every i in [0, n), each on its own pinned thread on
// core i (i = 0 on the calling thread), and returns when all are done.
typedef void (*idr_body)(void *env, int64_t index);
void idr_run_on_cores(int64_t n, idr_body body, void *env);

// Runs results[i] = task(env, i) for every i in [0, ntasks), spread over
// all cores: work items that idle cores take from one shared index, as
// futures would be stolen.
typedef int64_t (*idr_task)(void *env, int64_t index);
void idr_parallel(int64_t ntasks, idr_task task, void *env, int64_t *results);

// A single-producer, single-consumer channel of 64 entries.
void *idr_chan_new(void);
// Sends a reference the caller owns, after move-or-mark.
void idr_chan_send(void *chan, void *value);
// Waits for the next value.
void *idr_chan_recv(void *chan);

// Sending dead roots home (plan 5.6): `home` is a channel of 256 entries
// from a consumer back to its producer.
void *idr_home_new(void);
// A consumer drops a value that another core built. By default it drops it
// here, and every cell goes back to its owner as a remote free; built with
// IDR_GATE_HOME, it sends the dead root home, and the producer drops it
// locally.
void idr_drop_foreign(void *home, void *value);
// The producer's turn: drops the dead roots waiting in `home`. It must run
// before every send, so that `home` never fills.
void idr_producer_turn(void *home);
// The producer's end: with IDR_GATE_HOME, waits until all `sent` roots have
// come home and drops them.
void idr_producer_finish(void *home, int64_t sent);
// The end of a scheduler turn: with IDR_GATE_FLUSH, sends the allocator's
// batched remote frees now (snmalloc's flush) instead of when its cache
// fills (plan 5.6, 12.2 item 8).
void idr_turn_end(void);

// The program's entry point, defined by the lowered module.
int32_t idr_main(void);

#ifdef __cplusplus
}
#endif
