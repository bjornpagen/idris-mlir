// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// Reference counting and arrays against a model of what the runtime says
// they mean. Each case makes up to eight objects (cells of fields of a few
// object slots or of more than the header's objs field counts, arrays whose
// elements hold objects) and runs operations on them as compiled code does:
// references taken and dropped, stores into slots, copies of array views.
// A slot holds NULL, an odd word (a small big, or a grouped sum's group
// word), static data or an object made before its holder, so the heap is
// acyclic, as Idris's values are. Each word is counted by the entry for any
// word, which leaves NULL, an odd word and static data alone.
//
// The model knows only the meaning: an object's count is the references
// the test holds plus the slots of live objects that hold it, and an
// object is live while its count is above 0. After every operation the
// runtime must agree: the cells the checked runtime holds, each live
// object's count and exclusivity, each slot's word, static data untouched.
// A fixed list of cases foresees only the shapes its author thought of; a
// free that read a group word as a reference crashed past all of them, and
// this searches the shapes instead.
#include "idris_rt.h"
#include "prop.h"
#include "runtime.h"

#include <stdarg.h>
#include <stddef.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>

namespace {

// The fault the property must notice, planted in the model it holds the
// runtime to (prop.h): a free that walks only the slots a header's objs
// field can count, so a wide cell's later slots would keep what they hold.
// Planted, the model counts no reference of those slots, and the runtime,
// which does, disagrees with it once a wide cell holds an object there.
constexpr prop::Mutant objsFieldOnly{"counts only the slots a header's objs field can count, 254, of a wide cell"};

// The objects of a case: a chain, a sharing, an array holding boxes, a box
// holding an array and a wide cell holding the others fit in eight, and a
// failing case stays short enough to read.
constexpr unsigned objectLimit = 8;
// The operations of a case: eight objects, each made, stored into a few
// times and dropped.
constexpr unsigned stepLimit = 64;
// The object slots of a cell of fields: a few, the most the objs field
// counts (254), the field's mark (255, the least wide count), one past it
// and more. A wide cell's slots follow the word that counts them.
constexpr unsigned cellSlots[] = {0, 1, 2, 3, 254, 255, 256, 300};
constexpr unsigned slotLimit = 300;
// An array: up to 3 elements of up to 2 object slots each, then one plain
// word, so 8k + 8 bytes an element; a view's stride, 1 to 3, reaches every
// pattern of elements so few allow.
constexpr unsigned elementLimit = 3, elementSlotLimit = 2, strideLimit = 3;

// A slot's value, as an index into the words a slot may hold: the constant
// words first (NULL; the odd words 2x + 1, x from -2 to 3, which are the
// small bigs -2 to 2 and the group words of groups 0 to 3; the static box),
// then the objects in the order they were made. So object i is
// `constants + i`, and a slot of all zero bytes holds NULL.
using Value = uint16_t;
constexpr Value null = 0;
constexpr int oddLeast = -2, oddMost = 3;
constexpr Value firstOdd = 1;
constexpr Value staticBox = firstOdd + (oddMost - oddLeast + 1);
constexpr Value constants = staticBox + 1;

constexpr Value oddValue(int x) { return static_cast<Value>(firstOdd + (x - oddLeast)); }

// Static data, as idr-lower writes it: count 0, never counted, never freed.
constexpr uint32_t staticBoxInfo = idris_rt_info(0, 0, IDRIS_RT_KIND_FIELDS);
idris_rt_header staticBoxCell{0, staticBoxInfo};

// The families a slot's value is drawn from, simplest first.
enum ValueFamily : unsigned { Null, GroupWord, SmallBig, Static, Older, valueFamilies };
// The operations, simplest first: those that make an object, then those
// that act on one.
enum Operation : unsigned { MakeCell, MakeArray, Inc, Dec, Store, Copy, operations };
constexpr unsigned makings = Inc;

// What a case saw die, for the report: the most telling class names it.
enum Freed : unsigned { FreedAny = 1, FreedOdd = 2, FreedArray = 4, FreedWide = 8 };

// An object the case made: a cell of fields, one element of n slots, or an
// array of m elements of k slots each, `stride` bytes apart; its slots are
// numbered element after element, and `held` is what the model says each
// holds.
struct Object {
  char *first;
  uint32_t kind;
  unsigned elementSlots;
  size_t stride;
  unsigned elements;
  unsigned references;
  bool live;
  Value held[slotLimit];

  unsigned slots() const { return elements * elementSlots; }
  bool wide() const { return kind != IDRIS_RT_KIND_ARRAY && elementSlots >= IDRIS_RT_OBJS_WIDE; }
  void **slot(unsigned at) const {
    return reinterpret_cast<void **>(first + at / elementSlots * stride +
                                     at % elementSlots * IDRIS_RT_WORD_BYTES);
  }
};

// A rank-1 view, as a memref of rank 1 is laid out: the descriptor's three
// words, its size, its stride.
struct Memref1 {
  idris_rt_memref m;
  int64_t sizes[1], strides[1];
};
struct View {
  unsigned offset, stride;
};

class Model {
public:
  bool runCase(FuzzedDataProvider &p, prop::Tally &tally) {
    reset();
    // Swarm testing over two sets, neither ever empty: the ways to make an
    // object, and the ways to act on one. A case of only the second would
    // have nothing to act on.
    uint64_t enabled = prop::swarm(p, makings) | prop::swarm(p, operations - makings) << makings;
    values_ = prop::swarm(p, valueFamilies);
    for (unsigned steps = 0; steps < stepLimit && p.remaining_bytes() > 0; ++steps) {
      perform(p, static_cast<Operation>(prop::pick(p, enabled)));
      if (!agrees())
        return false;
    }
    // The end of a case: the test's references dropped.
    for (unsigned i = 0; i < made_; ++i) {
      while (objects_[i].references > 0) {
        note("dec #%u", i);
        --objects_[i].references;
        idris_rt_dec_any(words_[constants + i]);
        if (!agrees())
          return false;
      }
    }
    tally.classify(freed_ & FreedWide    ? "a wide cell freed"
                   : freed_ & FreedArray ? "an array holding objects freed"
                   : freed_ & FreedOdd   ? "a cell holding odd words freed"
                   : freed_ & FreedAny   ? "cells freed"
                                         : "nothing freed");
    return true;
  }

private:
  // Every case starts from the documented state: static data as written. A
  // case that failed may have left cells live; the count of held cells is
  // taken from here, so they do not count.
  void reset() {
    made_ = 0;
    freed_ = 0;
    step_ = 0;
    traced_ = 0;
    trace_[0] = '\0';
    staticBoxCell = idris_rt_header{0, staticBoxInfo};
    words_[null] = nullptr;
    for (int x = oddLeast; x <= oddMost; ++x)
      words_[oddValue(x)] = reinterpret_cast<void *>(static_cast<uintptr_t>(static_cast<uint64_t>(x) << 1 | 1));
    words_[staticBox] = &staticBoxCell;
    start_ = prop::held();
  }

  // The live objects among the first `before` made, into `out`; their count.
  unsigned liveBefore(unsigned before, unsigned *out) const {
    unsigned n = 0;
    for (unsigned i = 0; i < before; ++i)
      if (objects_[i].live)
        out[n++] = i;
    return n;
  }

  // A value for a slot of the object made `before`th, from the case's
  // families. When the
  // only families drawn are objects and none was made before the holder,
  // the slot holds NULL: there is nothing older to hold.
  Value drawValue(FuzzedDataProvider &p, unsigned before) {
    unsigned older[objectLimit];
    unsigned count = liveBefore(before, older);
    uint64_t families = count > 0 ? values_ : values_ & ~(uint64_t{1} << Older);
    if (families == 0)
      return null;
    switch (static_cast<ValueFamily>(prop::pick(p, families))) {
    case GroupWord:
      return oddValue(p.ConsumeIntegralInRange(0, 3));
    case SmallBig:
      return oddValue(p.ConsumeIntegralInRange(-2, 2));
    case Static:
      return staticBox;
    case Older:
      return static_cast<Value>(constants + older[p.ConsumeIntegralInRange(0u, count - 1)]);
    case Null:
    case valueFamilies:
      break;
    }
    return null;
  }

  // One operation. One with no operand to take (no object for it, or eight
  // made already) is skipped: the problem has such states, and the step
  // leaves the case as it was.
  void perform(FuzzedDataProvider &p, Operation operation) {
    unsigned chosen[objectLimit], n = 0;
    switch (operation) {
    case MakeCell:
      if (made_ < objectLimit)
        makeCell(p);
      return;
    case MakeArray:
      if (made_ < objectLimit)
        makeArray(p);
      return;
    case Inc:
      if ((n = liveBefore(made_, chosen)) > 0) {
        unsigned i = chosen[p.ConsumeIntegralInRange(0u, n - 1)];
        note("inc #%u", i);
        idris_rt_inc_any(words_[constants + i]);
        ++objects_[i].references;
      }
      return;
    case Dec:
      for (unsigned i = 0; i < made_; ++i)
        if (objects_[i].references > 0)
          chosen[n++] = i;
      if (n > 0) {
        unsigned i = chosen[p.ConsumeIntegralInRange(0u, n - 1)];
        note("dec #%u", i);
        --objects_[i].references;
        idris_rt_dec_any(words_[constants + i]);
      }
      return;
    case Store:
      store(p);
      return;
    case Copy:
      copy(p);
      return;
    case operations:
      return;
    }
  }

  // A cell of fields of n slots, each holding a drawn value with a
  // reference of the cell's own, taken first. Laid out as idr-lower lays it
  // out: the slots right after the header, or, past what objs counts, after
  // the word that counts them; one plain word after the slots.
  void makeCell(FuzzedDataProvider &p) {
    unsigned n = p.PickValueInArray(cellSlots);
    uint32_t tag = p.ConsumeIntegralInRange<uint32_t>(0, 3);
    bool wide = n >= IDRIS_RT_OBJS_WIDE;
    size_t head = wide ? 2 * IDRIS_RT_WORD_BYTES : IDRIS_RT_WORD_BYTES;
    auto *cell = reinterpret_cast<char *>(
        idris_rt_cell(head + IDRIS_RT_WORD_BYTES * n + IDRIS_RT_WORD_BYTES,
                      idris_rt_info(tag, wide ? IDRIS_RT_OBJS_WIDE : n, IDRIS_RT_KIND_FIELDS)));
    uint64_t count = n, plain = made_;
    if (wide)
      memcpy(cell + IDRIS_RT_WORD_BYTES, &count, sizeof count);
    memcpy(cell + head + IDRIS_RT_WORD_BYTES * n, &plain, sizeof plain);
    unsigned i = made_;
    Object &o = objects_[i];
    o.first = cell + head;
    o.kind = IDRIS_RT_KIND_FIELDS;
    o.elementSlots = n;
    o.stride = IDRIS_RT_WORD_BYTES * n;
    o.elements = 1;
    o.references = 1;
    o.live = true;
    words_[constants + i] = cell;
    for (unsigned at = 0; at < n; ++at) {
      Value v = drawValue(p, i);
      o.held[at] = v;
      idris_rt_inc_any(words_[v]);
      *o.slot(at) = words_[v];
    }
    ++made_;
    note("cell #%u of %u slots, tag %u", i, n, tag);
  }

  // An array of m elements of k slots each, every element written as the
  // array is made, each slot NULL, as a maker writes every element before
  // anything reads, releases or frees the array.
  void makeArray(FuzzedDataProvider &p) {
    unsigned m = p.ConsumeIntegralInRange(0u, elementLimit);
    unsigned k = p.ConsumeIntegralInRange(0u, elementSlotLimit);
    size_t stride = IDRIS_RT_WORD_BYTES * k + IDRIS_RT_WORD_BYTES;
    idris_rt_array *array = idris_rt_array_new_unwritten(
        m, idris_rt_info(static_cast<uint32_t>(stride), k, IDRIS_RT_KIND_ARRAY));
    memset(array + 1, 0, stride * m);
    unsigned i = made_;
    Object &o = objects_[i];
    o.first = reinterpret_cast<char *>(array + 1);
    o.kind = IDRIS_RT_KIND_ARRAY;
    o.elementSlots = k;
    o.stride = stride;
    o.elements = m;
    o.references = 1;
    o.live = true;
    memset(o.held, 0, sizeof o.held);
    words_[constants + i] = array;
    ++made_;
    note("array #%u of %u elements of %u slots", i, m, k);
  }

  // A store as compiled code makes one: the new value gains a reference,
  // then the slot's old value loses one.
  void store(FuzzedDataProvider &p) {
    unsigned holders[objectLimit], n = 0;
    for (unsigned i = 0; i < made_; ++i)
      if (objects_[i].live && objects_[i].slots() > 0)
        holders[n++] = i;
    if (n == 0)
      return;
    unsigned h = holders[p.ConsumeIntegralInRange(0u, n - 1)];
    Object &o = objects_[h];
    unsigned at = p.ConsumeIntegralInRange(0u, o.slots() - 1);
    Value v = drawValue(p, h);
    char text[16];
    note("#%u[%u] = %s", h, at, describe(v, text, sizeof text));
    idris_rt_inc_any(words_[v]);
    void *old = *o.slot(at);
    *o.slot(at) = words_[v];
    idris_rt_dec_any(old);
    o.held[at] = v;
  }

  // A view of `size` elements of an array of m: a stride that keeps them
  // inside it, and an offset where they fit.
  static View drawView(FuzzedDataProvider &p, unsigned m, unsigned size) {
    unsigned most = size <= 1 ? strideLimit : (m - 1) / (size - 1);
    unsigned stride = p.ConsumeIntegralInRange(1u, most < strideLimit ? most : strideLimit);
    unsigned reach = size == 0 ? 0 : (size - 1) * stride + 1;
    return View{p.ConsumeIntegralInRange(0u, m - reach), stride};
  }

  Memref1 descriptor(unsigned i, View view, unsigned size) const {
    auto *array = static_cast<idris_rt_array *>(words_[constants + i]);
    return Memref1{{array, objects_[i].first, view.offset}, {size}, {view.stride}};
  }

  // A rank-1 view of one array copied onto a view of another of the same
  // element, made after it (so every object the copy stores is older than
  // its new holder), or onto the identical view of the same array, the one
  // overlap idris_rt_memref_copy allows.
  void copy(FuzzedDataProvider &p) {
    unsigned arrays[objectLimit], n = 0;
    for (unsigned i = 0; i < made_; ++i)
      if (objects_[i].live && objects_[i].kind == IDRIS_RT_KIND_ARRAY)
        arrays[n++] = i;
    if (n == 0)
      return;
    unsigned a = arrays[p.ConsumeIntegralInRange(0u, n - 1)];
    unsigned targets[objectLimit], t = 0;
    targets[t++] = a;
    for (unsigned i = a + 1; i < made_; ++i)
      if (objects_[i].live && objects_[i].kind == IDRIS_RT_KIND_ARRAY &&
          objects_[i].elementSlots == objects_[a].elementSlots)
        targets[t++] = i;
    unsigned b = targets[p.ConsumeIntegralInRange(0u, t - 1)];
    Object &from = objects_[a];
    Object &to = objects_[b];
    unsigned room = from.elements < to.elements ? from.elements : to.elements;
    unsigned size = p.ConsumeIntegralInRange(0u, room);
    View source = drawView(p, from.elements, size);
    View target = a == b ? source : drawView(p, to.elements, size);
    note("copy #%u[%u, %u by %u] onto #%u[%u by %u]", a, source.offset, size, source.stride, b,
         target.offset, target.stride);
    Memref1 fromView = descriptor(a, source, size), toView = descriptor(b, target, size);
    idris_rt_memref_copy(1, &fromView.m, &toView.m);
    unsigned k = from.elementSlots;
    for (unsigned e = 0; e < size; ++e)
      for (unsigned s = 0; s < k; ++s)
        to.held[(target.offset + e * target.stride) * k + s] =
            from.held[(source.offset + e * source.stride) * k + s];
  }

  // The expected counts, from the meaning alone: the test's references,
  // plus each slot of a live object that holds the object. Every holder is
  // newer than what it holds, so walking from the newest object to the
  // oldest settles each one's count, and with it whether it lives, before
  // the objects it holds are reached. An object whose count reaches 0 is
  // dead for good.
  void settle(unsigned *counts) {
    for (unsigned i = 0; i < made_; ++i)
      counts[i] = objects_[i].references;
    for (unsigned j = made_; j-- > 0;) {
      Object &o = objects_[j];
      if (!o.live)
        continue;
      if (counts[j] == 0) {
        o.live = false;
        noteDeath(o);
        continue;
      }
      unsigned counted = o.wide() && prop::planted(objsFieldOnly) ? IDRIS_RT_OBJS_WIDE - 1 : o.slots();
      for (unsigned at = 0; at < counted; ++at)
        if (o.held[at] >= constants)
          ++counts[o.held[at] - constants];
    }
  }

  void noteDeath(const Object &o) {
    freed_ |= FreedAny;
    if (o.wide())
      freed_ |= FreedWide;
    for (unsigned at = 0; at < o.slots(); ++at) {
      if (o.held[at] >= firstOdd && o.held[at] < staticBox)
        freed_ |= FreedOdd;
      if (o.held[at] >= constants && o.kind == IDRIS_RT_KIND_ARRAY)
        freed_ |= FreedArray;
    }
  }

  // Whether the runtime agrees with the model after the step just noted.
  // The count of held cells comes first: a cell the model holds live is
  // read only once the runtime's count says it has not been freed.
  bool agrees() {
    unsigned counts[objectLimit];
    settle(counts);
    unsigned live = 0;
    for (unsigned i = 0; i < made_; ++i)
      live += objects_[i].live;
    uint64_t cells = prop::held() - start_;
    if (cells != live)
      return fails("%llu cells held, where the model has %u live objects",
                   static_cast<unsigned long long>(cells), live);
    for (unsigned i = 0; i < made_; ++i) {
      const Object &o = objects_[i];
      auto *header = static_cast<const idris_rt_header *>(words_[constants + i]);
      if (!o.live)
        continue;
      if (header->count != counts[i])
        return fails("#%u: count %u, where the model counts %u", i, header->count, counts[i]);
      auto *cell = const_cast<idris_rt_header *>(header);
      if (idris_rt_is_unique(cell) != (counts[i] == 1))
        return fails("#%u: idris_rt_is_unique is %d at count %u", i,
                     idris_rt_is_unique(cell) ? 1 : 0, counts[i]);
      if (!slotsAgree(i))
        return false;
    }
    if (staticBoxCell.count != 0 || staticBoxCell.info != staticBoxInfo)
      return fails("the static box: count %u, info %#x", staticBoxCell.count, staticBoxCell.info);
    return true;
  }

  // Whether each slot of object i holds the word the model says.
  bool slotsAgree(unsigned i) {
    const Object &o = objects_[i];
    for (unsigned at = 0; at < o.slots(); ++at)
      if (*o.slot(at) != words_[o.held[at]]) {
        char text[16];
        return fails("#%u: slot %u holds %p, where the model holds %s", i, at, *o.slot(at),
                     describe(o.held[at], text, sizeof text));
      }
    return true;
  }

  __attribute__((format(printf, 2, 3))) bool fails(const char *format, ...) {
    char why[256];
    va_list arguments;
    va_start(arguments, format);
    vsnprintf(why, sizeof why, format, arguments);
    va_end(arguments);
    prop::explain("after step %u: %s", step_, why);
    prop::explain("steps: %s", trace_);
    return false;
  }

  // A step of the case, counted, and kept for the explanation of a case
  // that fails.
  __attribute__((format(printf, 2, 3))) void note(const char *format, ...) {
    ++step_;
    if (traced_ + 3 >= sizeof trace_)
      return;
    if (traced_ > 0) {
      trace_[traced_++] = ';';
      trace_[traced_++] = ' ';
    }
    va_list arguments;
    va_start(arguments, format);
    vsnprintf(trace_ + traced_, sizeof trace_ - traced_, format, arguments);
    va_end(arguments);
    traced_ += strlen(trace_ + traced_);
  }

  static const char *describe(Value v, char *text, size_t room) {
    if (v >= constants)
      snprintf(text, room, "#%u", static_cast<unsigned>(v - constants));
    else if (v == staticBox)
      snprintf(text, room, "static");
    else if (v == null)
      snprintf(text, room, "NULL");
    else
      snprintf(text, room, "odd %d", 2 * (static_cast<int>(v - firstOdd) + oddLeast) + 1);
    return text;
  }

  Object objects_[objectLimit];
  unsigned made_ = 0;
  // Every word a slot may hold, by Value: the constants, then each object's
  // cell as it was made.
  void *words_[constants + objectLimit];
  uint64_t values_ = 0;
  uint64_t start_ = 0;
  unsigned step_ = 0;
  unsigned freed_ = 0;
  // Room for the steps of a case the explanation can show: 64 of a few
  // dozen bytes each.
  char trace_[3072];
  size_t traced_ = 0;
};

Model model;

int properties(int argc, char **argv) {
  prop::Run run(argc, argv);
  run.property("counting", objsFieldOnly, [](FuzzedDataProvider &provider, prop::Tally &tally) {
    return model.runCase(provider, tally);
  });
  return run.finish();
}

} // namespace

int main(int argc, char **argv) { return prop::onRuntime(argc, argv, "counting", properties); }
