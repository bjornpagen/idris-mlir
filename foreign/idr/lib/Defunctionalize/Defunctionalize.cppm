// idr.defunctionalize: closures of known labels become sums (sums). An
// analysis finds the labels each closure value may hold (analysis, over the
// lattice of labels, labels, and the module's closures, closures); every
// slot that holds a closure gets a key (slots); the keys that can become
// sums are decided (decided), and the module is rewritten (converter).
export module idr.defunctionalize;

export import :analysis;
export import :closures;
export import :converter;
export import :decided;
export import :labels;
export import :slots;
export import :sums;
