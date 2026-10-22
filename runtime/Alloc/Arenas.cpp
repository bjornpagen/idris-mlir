// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// Lifetimes a program allocates into by a bump: a chain of chunks and the
// cursor compiled code threads through it. Its cells carry no count and die
// together, when their lifetime ends: the chunks go back. Chunks come from the heap, so a lifetime's cells lie in
// the heap's span with every other and a strict host's limit counts them.
// PIN(runtime-quarantine) — see PINS.md
#include "Alloc/Alloc.h"
#include "End/End.h"
#include "Platform/Platform.h"
#include "idris_rt.h"

#include <stddef.h>
#include <stdint.h>

namespace {

// A chunk is its free bytes and then its trailer, which links the chunks
// of its chain both ways; the first word at a chain's cursor holds its
// chunk's trailer, so a cell that fits costs one load and one store.
struct Trailer {
  char *base;
  Trailer *older;
  Trailer *newer;
};

// The word at a cursor: its chunk's trailer, which every cell that fits
// moves on to the next cursor.
Trailer *&trailerAt(char *cursor) { return *reinterpret_cast<Trailer **>(cursor); }

// The trailer of the chunk any byte of its free bytes lies in, whatever the
// word at that byte now holds: a chunk is one allocation of exactly its
// size class, whose trailer is its last bytes. Out of line, at a chain's
// end alone.
Trailer *trailerOf(char *inside) {
  return reinterpret_cast<Trailer *>(inside + rt::alloc::bytesToEnd(inside) - sizeof(Trailer));
}

size_t bytesOf(const Trailer *trailer) {
  return static_cast<size_t>(reinterpret_cast<const char *>(trailer + 1) - trailer->base);
}

// A chunk whose free bytes hold `bytes` and the word after them, at least
// twice `older`'s and a page, the host's unit of memory, so a lifetime of
// any size takes a number of chunks logarithmic in it: newest of its chain,
// after `older`. Its first byte's word holds its trailer.
char *newChunk(Trailer *older, int64_t bytes) {
  size_t needed;
  if (__builtin_add_overflow(static_cast<uint64_t>(bytes), sizeof(Trailer *) + sizeof(Trailer),
                             &needed))
    rt::end::end(rt::end::OutOfMemory{});
  size_t size = older == nullptr ? 0 : bytesOf(older) * 2;
  if (size < needed)
    size = needed;
  if (size < rt::platform::pageSize())
    size = rt::platform::pageSize();
  size = rt::alloc::classSize(size);
  auto *base = static_cast<char *>(rt::alloc::allocate(size));
  auto *trailer = reinterpret_cast<Trailer *>(base + size - sizeof(Trailer));
  *trailer = Trailer{base, older, nullptr};
  if (older != nullptr)
    older->newer = trailer;
  trailerAt(base) = trailer;
  return base;
}

// Every chunk newer than `trailer`'s given back; it is the newest after.
void giveBackNewer(Trailer *trailer) {
  for (Trailer *newer = trailer->newer; newer != nullptr;) {
    Trailer *next = newer->newer;
    rt::alloc::release(newer->base);
    newer = next;
  }
  trailer->newer = nullptr;
}

// A cell that does not fit its cursor's chunk: a new chunk, the cell at its
// first byte, the word after the cell its trailer.
[[gnu::noinline]] char *chunkFor(char *cursor, int64_t bytes) {
  char *start = newChunk(cursor == nullptr ? nullptr : trailerAt(cursor), bytes);
  trailerAt(start + bytes) = trailerAt(start);
  return start;
}

} // namespace

// A chain's first cursor, its first chunk holding at least `size_hint`
// bytes, what the lifetime's callee said it puts; null for a hint of 0,
// which the first cell's chunk then starts.
extern "C" void *idris_rt_arena_open(int64_t size_hint) {
  return size_hint == 0 ? nullptr : newChunk(nullptr, size_hint);
}

// Where a cell of `bytes` goes in the chain of `cursor`: the cursor itself
// when its chunk holds the cell and the word after it, which takes the
// chunk's trailer on; else the first byte of a new chunk. Null starts a
// chain. The next cursor is the result plus `bytes`.
extern "C" [[gnu::always_inline]] void *idris_rt_arena_chunk(void *at, int64_t bytes) {
  auto *cursor = static_cast<char *>(at);
  if (cursor != nullptr) {
    Trailer *trailer = trailerAt(cursor);
    if (bytes <= reinterpret_cast<char *>(trailer) - cursor -
                     static_cast<ptrdiff_t>(sizeof(Trailer *))) [[likely]] {
      trailerAt(cursor + bytes) = trailer;
      return cursor;
    }
  }
  return chunkFor(cursor, bytes);
}

// The lifetime's end: every chunk of the chain of `cursor`, a byte of any of
// its chunks, given back in O(chunks); null gives back none.
extern "C" void idris_rt_arena_close(void *cursor) {
  if (cursor == nullptr)
    return;
  Trailer *trailer = trailerOf(static_cast<char *>(cursor));
  giveBackNewer(trailer);
  while (trailer != nullptr) {
    Trailer *older = trailer->older;
    rt::alloc::release(trailer->base);
    trailer = older;
  }
}

// A stack lifetime's end: the chunks of its chain taken since `mark`, the
// cursor when it opened, given back, and `mark` the chain's cursor again,
// its word its chunk's trailer once more. A null mark, a stack whose chain
// held no chunk when the lifetime opened, has no chunk to give back past.
extern "C" void idris_rt_stack_reset(void *mark) {
  if (mark == nullptr)
    return;
  auto *cursor = static_cast<char *>(mark);
  Trailer *trailer = trailerOf(cursor);
  giveBackNewer(trailer);
  trailerAt(cursor) = trailer;
}
