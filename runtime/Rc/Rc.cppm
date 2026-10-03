// rt.rc: reference counting over the header's count, and freeing. An object
// that dies releases its references from a worklist threaded through the
// dying cells themselves, as Lean's runtime frees (lean_del_core), so
// freeing a structure of any depth takes no recursion, no allocation and
// constant stack.
// PIN(runtime-quarantine) — see PINS.md
export module rt.rc;

export import :counting;
export import :freeing;
export import :objects;
