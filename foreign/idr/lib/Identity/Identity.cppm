// idr.identity: idr-identity, which makes every call of a function that
// gives back one of its arguments that argument. Once Idris's indices are
// erased, a function that only rebuilds its argument (Fin's weaken, a
// term's weakening to a larger scope) computes nothing: the parts of an
// argument (parts) are what its matches and reads take out of it, a
// function rebuilds one when every return is that part put back together
// (rebuilds), and the functions that do are found together, as the
// greatest fixpoint of what each assumes of the others (identities).
export module idr.identity;

export import :identities;
export import :parts;
export import :rebuilds;
