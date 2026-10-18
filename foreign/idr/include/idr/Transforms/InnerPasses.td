// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The steps of idr-optimize's inner pipeline that are ours, besides
// upstream's canonicalize and cse. Each reads what one run of idr-optimize holds (the
// ready set's summaries, the node table) and counts into idr-optimize's
// statistics, and is given all of it when it is made, by the factory its
// area's header declares: no other pipeline can hold one, so none is
// registered, and their declarations are generated without a registration.
// idr-optimize loads the dialects they make, and prints what they count.

#ifndef IDR_INNER_PASSES
#define IDR_INNER_PASSES

include "mlir/Pass/PassBase.td"

def IdrIdentity : Pass<"idr-identity", "::idr::FuncOp"> {
  let summary = "Make every call of a function that gives back one of its arguments that argument";
  let description = [{
    Once Idris's indices are erased, a function may only rebuild its
    argument: Data.Fin's weaken, finToNat and last, a term's weakening to a
    larger scope. Such a function gives back an argument x when every
    return is x rebuilt: x itself; a constructor where x is known to be
    that constructor (by the case of a match around the return, or as the
    one constructor of its type), each field the same field of x rebuilt;
    a constant where x is known to be that literal; the successor of x's
    predecessor; a match whose every region that returns yields x rebuilt;
    or a call assumed to give back what it is passed, passed x. The
    function must also only compute: every other op only allocates its
    results (a call as its `effects` say), a region that does not
    return ends in ub.unreachable, which Idris proved is never taken, and
    every call assumed to give back what it is passed either passes a part
    strictly below the function's argument (a field of a constructor of
    it, or the predecessor of a natural) or calls a function whose
    `effects` say it returns, so that every chain of such calls ends:
    values are finite. Its other arguments may be anything. The
    assumptions are the greatest fixpoint over each component of the ready
    set, solved when idr-optimize takes the component up, its callees'
    read as final. In each function, every call of such a function becomes
    its argument, at the quantity of the call's result; idr-optimize erases
    the function once nothing names it. A function of a program in the
    `owned` stage, or one that takes a world, gives back nothing. The first
    step of the inner pipeline; it counts into idr-optimize's
    `idr-identity.calls`.
  }];
  let constructor = "::idr::optimize::createIdentity(set, calls)";
}

def IdrRedirect : Pass<"idr-redirect", "::idr::FuncOp"> {
  let summary = "Call the specialization or raise node each call's key names";
  let description = [{
    Each call of a final callee whose arguments compose a key, or whose
    result a dispatch consumes, requests its key's node from idr-optimize's
    node table and calls it; the ready set builds what it requested. The
    per-function half of specialization, after cse, so that each call is
    read once the function is clean. It makes no function itself; it
    counts into idr-optimize's `idr-redirect.redirected`.
  }];
  let constructor = "::idr::optimize::createRedirect(nodes, redirected)";
}

def IdrConstants : Pass<"idr-constants", "::idr::FuncOp"> {
  let summary = "Propagate constants through one function, calls through their callees' summaries";
  let description = [{
    Sparse conditional constant propagation through one function, a call's
    results taken from its callee's summary: what the callee returns, read
    from its final body once its component is final. The last step, after
    idr-redirect, so that a function's final body states its summary; it
    counts into idr-optimize's `idr-constants.constants`.
  }];
  let constructor = "::idr::optimize::createConstants(set, constants)";
}

#endif // IDR_INNER_PASSES
