// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The thread's frame stack: where a recursion on a cycle of calls keeps its
// depth, a frame pushed once and popped once, so a push is a bump and a pop
// a store, inline in the program, with a chunk taken or given back on the
// slow paths. Chunks come from the heap, each at
// least twice the one below it, so a recursion of any depth takes a number
// of chunks logarithmic in it, and a strict host's limit counts them. The
// program is single-threaded: the stack is the runtime's.
#include "Alloc/Alloc.h"
#include "End/End.h"
#include "Platform/Platform.h"
#include "idris_rt.h"

#include <stddef.h>
#include <stdint.h>

namespace {

// A chunk begins with the chunk below it and where its own bytes end; its
// frames follow.
struct Chunk {
  Chunk *older;
  char *end;
};

// The newest chunk's first frame byte, the stack's top and the chunk's
// end: what a push and a pop read inline. All three are null while the
// stack has no chunk, which a push meets as no room.
char *first = nullptr;
char *top = nullptr;
char *limit = nullptr;

// The newest chunk, and the chunk the last pop that gave chunks back kept;
// null when there is none.
Chunk *newest = nullptr;
Chunk *spare = nullptr;

char *framesOf(Chunk *chunk) { return reinterpret_cast<char *>(chunk + 1); }

size_t bytesOf(const Chunk *chunk) {
  return static_cast<size_t>(chunk->end - reinterpret_cast<const char *>(chunk));
}

// A chunk given back: the larger of it and the spare is kept.
void giveBack(Chunk *chunk) {
  if (spare != nullptr && bytesOf(spare) >= bytesOf(chunk)) {
    rt::alloc::release(chunk);
    return;
  }
  if (spare != nullptr)
    rt::alloc::release(spare);
  spare = chunk;
}

// A push the newest chunk has no room for: the spare when it holds the
// frame, else a new chunk at least twice the newest, the frame and a page.
[[gnu::noinline]] char *pushPast(int64_t bytes) {
  size_t frame = static_cast<size_t>(bytes);
  Chunk *chunk = spare;
  if (chunk != nullptr && bytesOf(chunk) - sizeof(Chunk) >= frame) {
    spare = nullptr;
  } else {
    size_t needed;
    if (__builtin_add_overflow(frame, sizeof(Chunk), &needed))
      rt::end::end(rt::end::OutOfMemory{});
    size_t size = newest == nullptr ? 0 : bytesOf(newest) * 2;
    if (size < needed)
      size = needed;
    if (size < rt::platform::pageSize())
      size = rt::platform::pageSize();
    size = rt::alloc::classSize(size);
    chunk = static_cast<Chunk *>(rt::alloc::allocate(size));
    chunk->end = reinterpret_cast<char *>(chunk) + size;
  }
  chunk->older = newest;
  newest = chunk;
  first = framesOf(chunk);
  limit = chunk->end;
  top = first + frame;
  return first;
}

// A pop to a frame of an older chunk: every chunk newer than the frame's is
// given back, the frame's chunk the newest again.
[[gnu::noinline]] void popPast(char *frame) {
  Chunk *chunk = newest;
  while (!(frame >= framesOf(chunk) && frame < chunk->end)) {
    Chunk *older = chunk->older;
    giveBack(chunk);
    chunk = older;
  }
  newest = chunk;
  first = framesOf(chunk);
  limit = chunk->end;
  top = frame;
}

} // namespace

// The next frame's `bytes` on the stack, contiguous: a bump of the top
// when the newest chunk holds them.
extern "C" [[gnu::always_inline]] idris_rt_header *idris_rt_frame_push(int64_t bytes) {
  if (bytes <= limit - top) [[likely]] {
    char *frame = top;
    top += bytes;
    return reinterpret_cast<idris_rt_header *>(frame);
  }
  return reinterpret_cast<idris_rt_header *>(pushPast(bytes));
}

// The stack back to `frame`, a frame it pushed: the top put back when the
// frame lies in the newest chunk, which stays the newest even emptied, so a
// push after it takes no chunk.
extern "C" [[gnu::always_inline]] void idris_rt_frame_pop(idris_rt_header *popped) {
  auto *frame = reinterpret_cast<char *>(popped);
  if (frame >= first && frame < limit) [[likely]] {
    top = frame;
    return;
  }
  popPast(frame);
}
