// idr.defunctionalize: closures and suspensions of known labels become sums
// (sums). An analysis finds the labels each closure or suspension may hold
// (analysis, over the lattice of labels, labels, and the module's closures,
// closures); every slot that holds one gets a key (slots), and values move
// between slots (moves); the keys that can become sums are decided
// (decided), declared (declared), and the module is rewritten (converter);
// then the labels of memo sums that must run at every force are marked
// (byname).
export module idr.defunctionalize;

export import :analysis;
export import :byname;
export import :closures;
export import :converter;
export import :decided;
export import :declared;
export import :labels;
export import :moves;
export import :slots;
export import :sums;
