// idr.ops:ioeffects: the effects of the ops on buffers and arrays: their IO
// is in the world's order, as every other IO op's.
export module idr.ops:ioeffects;

import idr.mlir;
import idr.dialect;

using namespace mlir;
using namespace idr;

export namespace idr::ops {

// What an op on a buffer or an array does besides computing: IO in the
// world's order, a crash where its range or index may be out of bounds
// (`crash`), and for a new array an allocation (`allocated`, or null).
void ioEffects(std::optional<StringRef> crash, Value allocated,
               SmallVectorImpl<SideEffects::EffectInstance<MemoryEffects::Effect>> &effects) {
  effects.emplace_back(MemoryEffects::Read::get(), IOResource::get());
  effects.emplace_back(MemoryEffects::Write::get(), IOResource::get());
  if (crash)
    effects.emplace_back(MemoryEffects::Write::get(), CrashResource::get());
  if (allocated)
    effects.emplace_back(MemoryEffects::Allocate::get(), cast<OpResult>(allocated),
                         SideEffects::DefaultResource::get());
}

} // namespace idr::ops
