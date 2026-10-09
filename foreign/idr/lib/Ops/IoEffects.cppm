// idr.ops:ioeffects: the effects of the ops on buffers and arrays: their IO
// is in the world's order, as every other IO op's.
export module idr.ops:ioeffects;

import idr.mlir;
import idr.dialect;

using namespace mlir;
using namespace idr;

export namespace idr::ops {

// What an op on a buffer or an array does besides computing: IO in the
// world's order, and for a new array or string an allocation (`allocated`,
// or null). A range or an index it reads is its guard's to check.
void ioEffects(Value allocated,
               SmallVectorImpl<SideEffects::EffectInstance<MemoryEffects::Effect>> &effects) {
  effects.emplace_back(MemoryEffects::Read::get(), IOResource::get());
  effects.emplace_back(MemoryEffects::Write::get(), IOResource::get());
  if (allocated)
    effects.emplace_back(MemoryEffects::Allocate::get(), cast<OpResult>(allocated),
                         SideEffects::DefaultResource::get());
}

} // namespace idr::ops
