-- SPDX-License-Identifier: 0BSD
-- Copyright (c) 2026 Bjorn Pagen
||| The walk's markers as the host's substitution lemma takes them, and
||| what follows from their freshness.
|||
||| A marker is a bound name of the compiler's own vocabulary, which no
||| source spells (`Frontend.Walk.probeName`), so no definition of the
||| frozen context names one: the markers are fresh for the context
||| (`Idris.Host.FreshIn`). That is a fact of the context the walk reads,
||| carried with the markers' bounds (`Markers`) and never tested. From
||| it, a definition's one leaf names none of the markers (`leafFresh`),
||| and that leaf, with the markers put in for its parameters, names no
||| unknown by them (`closedNoUnknown`): the two premises the host's
||| substitution lemma (`Idris.Host.substitutes`) asks of what it reduces.
|||
||| Every proof is erased and total, and nothing here runs.
module IdrisMLIR.Proof.Markers

import Core.Case.CaseTree
import Core.Context
import Core.TT
import Idris.Host
import Libraries.Data.List.SizeOf

-- Nothing here names a length's constructors, but the proofs unfold the
-- sizes' public definitions (`range` and `varAt` over `SizeOf`, which
-- holds a `HasLength`), and Idris unfolds only what an import loads.
import Data.List.HasLength

%default total

||| The walk's markers for a scope's variables: the bounds that turn each
||| marker back into the variable it stands for, the evidence that their
||| names are apart, and the evidence that no definition of the context
||| names one.
public export
record Markers (ctx : Frozen) (ns : Scope) where
  constructor MkMarkers
  bounds : Bounds ns
  0 apart : namesApart bounds = True
  0 fresh : FreshIn ctx bounds

||| A definition's one leaf names none of the markers: the context reads
||| its tree, and no tree it reads names one.
export
0 leafFresh : {0 bs : Bounds ns} -> FreshIn ctx bs -> Defines ctx j d -> definition d = PMDef info args body ->
              TreeOf body (STerm i rhs) -> mentions BoundOrUnknown bs rhs = False
leafFresh fresh defines isDef tree = fresh defines isDef tree

------------------------------------------------------------------------------
-- Markers name no unknown
------------------------------------------------------------------------------

-- No naming finds a name in a local.
0 localUnnamed : LocalAt fc r i t -> mentions k bs t = False
localUnnamed IsLocalAt = Refl

-- The marker at a variable of a scope is a bound reference to the name
-- its bounds replace there.
0 markerNamed : (bs : Bounds ns) -> (w : Var ns) ->
                Var.index (markersOf {vars} fc bs) w = Ref fc Bound (replacedAt bs w)
markerNamed (Add _ old rest) (MkVar First) = Refl
markerNamed (Add _ _ rest) (MkVar (Later v)) = markerNamed rest (MkVar v)
markerNamed None (MkVar v) impossible

0 orFalse : (a : Bool) -> (a || b) = False -> (a = False, b = False)
orFalse False prf = (Refl, prf)
orFalse True prf = absurd prf

0 orBoth : {a, b : Bool} -> a = False -> b = False -> (a || b) = False
orBoth Refl Refl = Refl

-- A local, with the markers put in for the scope's variables: a local
-- below the binders or past the scope, or a marker, which is a bound
-- reference, never an unknown. The local's location and kind are given to
-- the substitution lemmas: their equations name a local of their own, which
-- is the goal's only once given as the goal's.
0 markedLocal : (o : SizeOf outer) -> (sz : SizeOf ns) -> (bs : Bounds ns) ->
                (0 p : IsVar nm i (outer ++ (ns ++ vars))) ->
                mentions UnknownOnly bs (substTerm o sz (markersOf {vars} fc bs) (Local lfc r i p)) = False
markedLocal o sz bs p = case range (size o) (size sz) i of
  InFirst lt => localUnnamed (substBelow {fc = lfc} {r} o sz (markersOf {vars} fc bs) p lt)
  InSecond j eq lt =>
    let (w ** wj) = varAt sz j lt in
    rewrite substMiddle {fc = lfc} {r} o sz (markersOf {vars} fc bs) p w (trans eq (cong (size o +) (sym wj))) in
    rewrite the (weakenNs o (Var.index (markersOf {vars} fc bs) w) = Ref fc Bound (replacedAt bs w))
                (trans (cong (weakenNs o) (markerNamed bs w)) weakenRef) in
    Refl
  PastBoth k eq => localUnnamed (substPast {fc = lfc} {r} o sz (markersOf {vars} fc bs) p k eq)

mutual
  ||| A term over a scope, under binders, with the markers put in for the
  ||| scope's variables, names no unknown by them where it names none of
  ||| them itself: every marker put in is a bound reference, and every
  ||| unknown it holds is one it held.
  export
  0 markedNoUnknown : (o : SizeOf outer) -> (sz : SizeOf ns) -> (bs : Bounds ns) ->
                      (u : Term (outer ++ (ns ++ vars))) -> mentions BoundOrUnknown bs u = False ->
                      mentions UnknownOnly bs (substTerm o sz (markersOf {vars} fc bs) u) = False
  markedNoUnknown o sz bs (Local lfc r i p) _ = markedLocal o sz bs p
  markedNoUnknown o sz bs (Ref rfc Bound n) _ = Refl
  markedNoUnknown o sz bs (Ref rfc Func n) _ = Refl
  markedNoUnknown o sz bs (Ref rfc (DataCon tag arity) n) _ = Refl
  markedNoUnknown o sz bs (Ref rfc (TyCon arity) n) _ = Refl
  markedNoUnknown o sz bs (Meta mfc m k args) none =
    orBoth (fst (orFalse (replaces bs m) none)) (markedNoUnknownAll o sz bs args (snd (orFalse (replaces bs m) none)))
  markedNoUnknown o sz bs (Bind bfc x b sc) none =
    orBoth (markedNoUnknownBinder o sz bs b (fst (orFalse (mentionsInBinder BoundOrUnknown bs b) none)))
           (markedNoUnknown (suc o) sz bs sc (snd (orFalse (mentionsInBinder BoundOrUnknown bs b) none)))
  markedNoUnknown o sz bs (App afc f a) none =
    orBoth (markedNoUnknown o sz bs f (fst (orFalse (mentions BoundOrUnknown bs f) none)))
           (markedNoUnknown o sz bs a (snd (orFalse (mentions BoundOrUnknown bs f) none)))
  markedNoUnknown o sz bs (As afc side n t) none =
    orBoth (markedNoUnknown o sz bs n (fst (orFalse (mentions BoundOrUnknown bs n) none)))
           (markedNoUnknown o sz bs t (snd (orFalse (mentions BoundOrUnknown bs n) none)))
  markedNoUnknown o sz bs (TDelayed dfc r t) none = markedNoUnknown o sz bs t none
  markedNoUnknown o sz bs (TDelay dfc d ty a) none =
    orBoth (markedNoUnknown o sz bs ty (fst (orFalse (mentions BoundOrUnknown bs ty) none)))
           (markedNoUnknown o sz bs a (snd (orFalse (mentions BoundOrUnknown bs ty) none)))
  markedNoUnknown o sz bs (TForce ffc r t) none = markedNoUnknown o sz bs t none
  markedNoUnknown o sz bs (PrimVal pfc c) _ = Refl
  markedNoUnknown o sz bs (Erased efc Placeholder) _ = Refl
  markedNoUnknown o sz bs (Erased efc Impossible) _ = Refl
  markedNoUnknown o sz bs (Erased efc (Dotted t)) none = markedNoUnknown o sz bs t none
  markedNoUnknown o sz bs (TType tfc u) _ = Refl

  0 markedNoUnknownAll : (o : SizeOf outer) -> (sz : SizeOf ns) -> (bs : Bounds ns) ->
                         (us : List (Term (outer ++ (ns ++ vars)))) -> mentionsIn BoundOrUnknown bs us = False ->
                         mentionsIn UnknownOnly bs (substTerms o sz (markersOf {vars} fc bs) us) = False
  markedNoUnknownAll o sz bs [] _ = Refl
  markedNoUnknownAll o sz bs (u :: us) none =
    orBoth (markedNoUnknown o sz bs u (fst (orFalse (mentions BoundOrUnknown bs u) none)))
           (markedNoUnknownAll o sz bs us (snd (orFalse (mentions BoundOrUnknown bs u) none)))

  0 markedNoUnknownBinder : (o : SizeOf outer) -> (sz : SizeOf ns) -> (bs : Bounds ns) ->
                            (b : Binder (Term (outer ++ (ns ++ vars)))) -> mentionsInBinder BoundOrUnknown bs b = False ->
                            mentionsInBinder UnknownOnly bs (substBinder o sz (markersOf {vars} fc bs) b) = False
  markedNoUnknownBinder o sz bs (Lam lfc c p ty) none =
    orBoth (markedNoUnknownPi o sz bs p (fst (orFalse (mentionsInPi BoundOrUnknown bs p) none)))
           (markedNoUnknown o sz bs ty (snd (orFalse (mentionsInPi BoundOrUnknown bs p) none)))
  markedNoUnknownBinder o sz bs (Let lfc c v ty) none =
    orBoth (markedNoUnknown o sz bs v (fst (orFalse (mentions BoundOrUnknown bs v) none)))
           (markedNoUnknown o sz bs ty (snd (orFalse (mentions BoundOrUnknown bs v) none)))
  markedNoUnknownBinder o sz bs (Pi lfc c p ty) none =
    orBoth (markedNoUnknownPi o sz bs p (fst (orFalse (mentionsInPi BoundOrUnknown bs p) none)))
           (markedNoUnknown o sz bs ty (snd (orFalse (mentionsInPi BoundOrUnknown bs p) none)))
  markedNoUnknownBinder o sz bs (PVar lfc c p ty) none =
    orBoth (markedNoUnknownPi o sz bs p (fst (orFalse (mentionsInPi BoundOrUnknown bs p) none)))
           (markedNoUnknown o sz bs ty (snd (orFalse (mentionsInPi BoundOrUnknown bs p) none)))
  markedNoUnknownBinder o sz bs (PLet lfc c v ty) none =
    orBoth (markedNoUnknown o sz bs v (fst (orFalse (mentions BoundOrUnknown bs v) none)))
           (markedNoUnknown o sz bs ty (snd (orFalse (mentions BoundOrUnknown bs v) none)))
  markedNoUnknownBinder o sz bs (PVTy lfc c ty) none = markedNoUnknown o sz bs ty none

  0 markedNoUnknownPi : (o : SizeOf outer) -> (sz : SizeOf ns) -> (bs : Bounds ns) ->
                        (p : PiInfo (Term (outer ++ (ns ++ vars)))) -> mentionsInPi BoundOrUnknown bs p = False ->
                        mentionsInPi UnknownOnly bs (substPi o sz (markersOf {vars} fc bs) p) = False
  markedNoUnknownPi o sz bs Implicit _ = Refl
  markedNoUnknownPi o sz bs Explicit _ = Refl
  markedNoUnknownPi o sz bs AutoImplicit _ = Refl
  markedNoUnknownPi o sz bs (DefImplicit t) none = markedNoUnknown o sz bs t none

||| A term over a scope, closed with the markers in for its variables,
||| names no unknown by them where it names none of them itself.
export
0 closedNoUnknown : {ns : Scope} -> (bs : Bounds ns) -> (t : Term ns) -> mentions BoundOrUnknown bs t = False ->
                    mentions UnknownOnly bs (substs (mkSizeOf ns) (markersOf {vars = []} fc bs) (embed {outer = []} t)) = False
closedNoUnknown bs t none =
  markedNoUnknown {vars = []} zero (mkSizeOf ns) bs (embed {outer = []} t)
                  (trans (mentionsEmbed {outer = []} BoundOrUnknown bs t) none)
