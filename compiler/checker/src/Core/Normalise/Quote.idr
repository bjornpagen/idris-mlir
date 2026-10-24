-- SPDX-License-Identifier: BSD-3-Clause
-- Copyright (c) 2020 Edwin Brady
module Core.Normalise.Quote

import Core.Context
import Core.Env
import Core.Normalise.Eval
import Core.Value

%default covering

export
data QVar : Type where

||| A quote that follows stuck applications only so deep: the term, or the
||| news that it is deeper, where the caller then quotes another way. The
||| depth decides only how much work a stored term's form costs, never
||| whether a program is accepted.
public export
data Quoted : Scoped where
  WithinDepth : Term vars -> Quoted vars
  TooDeep : Quoted vars

||| How deep a quote follows stuck applications. A quote hands what it builds
||| to a continuation, whose answer has type `answer`: the whole term, for any
||| answer; or only up to a depth, for a quote whose answer is `Quoted`, so
||| the depth reached answers `TooDeep` and ends the quote, as no other quote
||| can.
public export
data Depth : Type -> Type where
  Whole : Depth answer
  UpTo : Nat -> Depth (Quoted vars)

public export
record QuoteOpts answer where
  constructor MkQuoteOpts
  topLevel : Bool -- At the top level application
  patterns : Bool -- only quote as far as is useful to get LHS patterns.
                  -- That means, stop on encountering a block function or
                  -- local
  depth : Depth answer

public export
interface Quote tm where
    quote : {auto c : Ref Ctxt Defs} ->
            {vars : Scope} ->
            Defs -> Env Term vars -> tm vars -> Core (Term vars)
    quoteLHS : {auto c : Ref Ctxt Defs} ->
               {vars : Scope} ->
               Defs -> Env Term vars -> tm vars -> Core (Term vars)
    ||| Quoting with stuck applications followed at most `limit` deep.
    quoteWithin : {auto c : Ref Ctxt Defs} ->
                  {vars : Scope} ->
                  (limit : Nat) -> Defs -> Env Term vars -> tm vars -> Core (Quoted vars)

    quoteGen : {auto c : Ref Ctxt Defs} ->
               {vars : _} ->
               Ref QVar Int -> QuoteOpts answer ->
               Defs -> Env Term vars -> tm vars ->
               (Term vars -> Core answer) -> Core answer

    quote defs env tm
        = do q <- newRef QVar 0
             quoteGen q (MkQuoteOpts True False Whole) defs env tm (\t => pure t)

    quoteLHS defs env tm
        = do q <- newRef QVar 0
             quoteGen q (MkQuoteOpts True True Whole) defs env tm (\t => pure t)

    quoteWithin limit defs env tm
        = do q <- newRef QVar 0
             quoteGen q (MkQuoteOpts False False (UpTo limit)) defs env tm
                      (\t => pure (WithinDepth t))

export
genName : {auto q : Ref QVar Int} -> Ident -> Core Name
genName n
    = do i <- get QVar
         put QVar (i + 1)
         pure (MN n i)

-- One stuck application deeper: the quote goes on with the depth left, or,
-- with none left, answers that the term is deeper.
deeper : Depth answer -> (Depth answer -> Core answer) -> Core answer
deeper Whole go = go Whole
deeper (UpTo Z) go = pure TooDeep
deeper (UpTo (S k)) go = go (UpTo k)

-- Each in turn, in order, what each gives handed on together.
quoteEach : (a -> (b -> Core answer) -> Core answer) ->
            List a -> (List b -> Core answer) -> Core answer
quoteEach go [] k = k []
quoteEach go (x :: xs) k = go x $ \y => quoteEach go xs $ \ys => k (y :: ys)

-- Why a part is erased, a dotted term quoted by `go`.
quoteErased : (a -> (b -> Core answer) -> Core answer) ->
              WhyErased a -> (WhyErased b -> Core answer) -> Core answer
quoteErased go Placeholder k = k Placeholder
quoteErased go Impossible k = k Impossible
quoteErased go (Dotted t) k = go t $ \t' => k (Dotted t')

mutual
  quoteArg : {auto c : Ref Ctxt Defs} ->
              {bound, free : _} ->
              Ref QVar Int -> QuoteOpts answer -> Defs -> Bounds bound ->
              Env Term free -> Closure free ->
              (Term (bound ++ free) -> Core answer) -> Core answer
  quoteArg q opts defs bounds env a k
      = quoteGenNF q opts defs bounds env !(evalClosure defs a) k

  quoteArgWithFC : {auto c : Ref Ctxt Defs} ->
                   {bound, free : _} ->
                   Ref QVar Int -> QuoteOpts answer -> Defs -> Bounds bound ->
                   Env Term free -> (FC, Closure free) ->
                   ((FC, Term (bound ++ free)) -> Core answer) -> Core answer
  quoteArgWithFC q opts defs bounds env (fc, a) k
       = quoteArg q opts defs bounds env a $ \a' => k (fc, a')

  quoteArgs : {auto c : Ref Ctxt Defs} ->
              {bound, free : _} ->
              Ref QVar Int -> QuoteOpts answer -> Defs -> Bounds bound ->
              Env Term free -> List (Closure free) ->
              (List (Term (bound ++ free)) -> Core answer) -> Core answer
  quoteArgs q opts defs bounds env = quoteEach (quoteArg q opts defs bounds env)

  quoteArgsWithFC : {auto c : Ref Ctxt Defs} ->
                    {bound, free : _} ->
                    Ref QVar Int -> QuoteOpts answer -> Defs -> Bounds bound ->
                    Env Term free -> List (FC, Closure free) ->
                    (List (FC, Term (bound ++ free)) -> Core answer) -> Core answer
  quoteArgsWithFC q opts defs bounds env
      = quoteEach (quoteArgWithFC q opts defs bounds env)

  quoteHead : {auto c : Ref Ctxt Defs} ->
              {bound, free : _} ->
              Ref QVar Int -> QuoteOpts answer -> Defs ->
              FC -> Bounds bound -> Env Term free -> NHead free ->
              (Term (bound ++ free) -> Core answer) -> Core answer
  quoteHead {bound} q opts defs fc bounds env (NLocal mrig _ prf) k
      = let MkVar prf' = addLater bound prf in
            k (Local fc mrig _ prf')
    where
      addLater : {idx : _} ->
                 (ys : List Name) -> (0 p : IsVar n idx xs) ->
                 Var (ys ++ xs)
      addLater [] isv = MkVar isv
      addLater (x :: xs) isv
          = let MkVar isv' = addLater xs isv in
                MkVar (Later isv')
  -- A bound reference is one of this quote's binders only when it is that
  -- binder's name, compared whole, as every other reader resolves a bound
  -- name (`refsToLocals`). The conversion check, the unifier, the case
  -- builder and the compiler's frontend make bound machine names of their
  -- own, each numbering from zero as this quote numbers its binders, so a
  -- number alone took such a name for the binder of that number: the
  -- conversion check's eta step equated `\x => \z => k (\y => y) z` with
  -- `\x => k (\y => x)`. Identifiers are interned, so the whole comparison
  -- is two comparisons of integers. The binders are the names `genName`
  -- makes, machine names, so a name of another form is none of them.
  quoteHead {free} q opts defs fc bounds env (NRef Bound n@(MN {})) k
      = k (refsToLocals {vars = free} bounds (Ref fc Bound n))
  quoteHead q opts defs fc bounds env (NRef nt n) k = k (Ref fc nt n)
  quoteHead q opts defs fc bounds env (NMeta n i args) k
      = quoteArgs q opts defs bounds env args $ \args' => k (Meta fc n i args')

  quotePi : {auto c : Ref Ctxt Defs} ->
            {bound, free : _} ->
            Ref QVar Int -> QuoteOpts answer -> Defs -> Bounds bound ->
            Env Term free -> PiInfo (Closure free) ->
            (PiInfo (Term (bound ++ free)) -> Core answer) -> Core answer
  quotePi q opts defs bounds env Explicit k = k Explicit
  quotePi q opts defs bounds env Implicit k = k Implicit
  quotePi q opts defs bounds env AutoImplicit k = k AutoImplicit
  quotePi q opts defs bounds env (DefImplicit t) k
      = quoteGenNF q opts defs bounds env !(evalClosure defs t) $ \t' =>
          k (DefImplicit t')

  quoteBinder : {auto c : Ref Ctxt Defs} ->
                {bound, free : _} ->
                Ref QVar Int -> QuoteOpts answer -> Defs -> Bounds bound ->
                Env Term free -> Binder (Closure free) ->
                (Binder (Term (bound ++ free)) -> Core answer) -> Core answer
  quoteBinder q opts defs bounds env (Lam fc r p ty) k
      = quoteGenNF q opts defs bounds env !(evalClosure defs ty) $ \ty' =>
          quotePi q opts defs bounds env p $ \p' =>
            k (Lam fc r p' ty')
  quoteBinder q opts defs bounds env (Let fc r val ty) k
      = quoteGenNF q opts defs bounds env !(evalClosure defs val) $ \val' =>
          do tyNF <- evalClosure defs ty
             quoteGenNF q opts defs bounds env tyNF $ \ty' =>
               k (Let fc r val' ty')
  quoteBinder q opts defs bounds env (Pi fc r p ty) k
      = quoteGenNF q opts defs bounds env !(evalClosure defs ty) $ \ty' =>
          quotePi q opts defs bounds env p $ \p' =>
            k (Pi fc r p' ty')
  quoteBinder q opts defs bounds env (PVar fc r p ty) k
      = quoteGenNF q opts defs bounds env !(evalClosure defs ty) $ \ty' =>
          quotePi q opts defs bounds env p $ \p' =>
            k (PVar fc r p' ty')
  quoteBinder q opts defs bounds env (PLet fc r val ty) k
      = quoteGenNF q opts defs bounds env !(evalClosure defs val) $ \val' =>
          do tyNF <- evalClosure defs ty
             quoteGenNF q opts defs bounds env tyNF $ \ty' =>
               k (PLet fc r val' ty')
  quoteBinder q opts defs bounds env (PVTy fc r ty) k
      = quoteGenNF q opts defs bounds env !(evalClosure defs ty) $ \ty' =>
          k (PVTy fc r ty')

  quoteGenNF : {auto c : Ref Ctxt Defs} ->
               {bound, vars : _} ->
               Ref QVar Int -> QuoteOpts answer ->
               Defs -> Bounds bound ->
               Env Term vars -> NF vars ->
               (Term (bound ++ vars) -> Core answer) -> Core answer
  quoteGenNF q opts defs bound env (NBind fc n b sc) k
      = do var <- genName (known Kqv)
           scNF <- sc defs (toClosure defaultOpts env (Ref fc Bound var))
           quoteGenNF q opts defs (Add n var bound) env scNF $ \sc' =>
             quoteBinder q opts defs bound env b $ \b' =>
               k (Bind fc n b' sc')
  quoteGenNF q opts defs bound env (NApp fc f args) k
      = quoteHead q opts defs fc bound env f $ \f' =>
          deeper opts.depth $ \d =>
            let opts' = { depth := d } opts in
                if patterns opts && not (topLevel opts) && isRef f
                   then do empty <- clearDefs defs
                           quoteArgsWithFC q opts' empty bound env args $ \args' =>
                             k (applyStackWithFC f' args')
                   else quoteArgsWithFC q ({ topLevel := False } opts')
                                        defs bound env args $ \args' =>
                          k (applyStackWithFC f' args')
    where
      isRef : NHead vars -> Bool
      isRef (NRef {}) = True
      isRef _ = False
  quoteGenNF q opts defs bound env (NDCon fc n t ar args) k
      = quoteArgsWithFC q opts defs bound env args $ \args' =>
          k (applyStackWithFC (Ref fc (DataCon t ar) n) args')
  quoteGenNF q opts defs bound env (NTCon fc n ar args) k
      = quoteArgsWithFC q opts defs bound env args $ \args' =>
          k (applyStackWithFC (Ref fc (TyCon ar) n) args')
  quoteGenNF q opts defs bound env (NAs fc s n pat) k
      = quoteGenNF q opts defs bound env n $ \n' =>
          quoteGenNF q opts defs bound env pat $ \pat' =>
            k (As fc s n' pat')
  quoteGenNF q opts defs bound env (NDelayed fc r arg) k
      = quoteGenNF q opts defs bound env arg $ \argQ =>
          k (TDelayed fc r argQ)
  quoteGenNF q opts defs bound env (NDelay fc r ty arg) k
      = do argNF <- evalClosure defs (toHolesOnly arg)
           quoteGenNF q opts defs bound env argNF $ \argQ =>
             do tyNF <- evalClosure defs (toHolesOnly ty)
                quoteGenNF q opts defs bound env tyNF $ \tyQ =>
                  k (TDelay fc r tyQ argQ)
    where
      toHolesOnly : Closure vs -> Closure vs
      toHolesOnly (MkClosure opts locs env tm)
          = MkClosure ({ holesOnly := True,
                         argHolesOnly := True } opts)
                      locs env tm
      toHolesOnly c = c
  quoteGenNF q opts defs bound env (NForce fc r arg args) k
      = quoteArgsWithFC q opts defs bound env args $ \args' =>
          case arg of
               NDelay fc _ _ arg =>
                  do argNF <- evalClosure defs arg
                     quoteGenNF q opts defs bound env argNF $ \argQ =>
                       k (applyStackWithFC argQ args')
               _ => quoteGenNF q opts defs bound env arg $ \arg' =>
                      k (applyStackWithFC (TForce fc r arg') args')
  quoteGenNF q opts defs bound env (NPrimVal fc c) k = k (PrimVal fc c)
  quoteGenNF q opts defs bound env (NErased fc t) k
      = quoteErased (quoteGenNF q opts defs bound env) t $ \t' => k (Erased fc t')
  quoteGenNF q opts defs bound env (NType fc u) k = k (TType fc u)

export
Quote NF where
  quoteGen q opts defs env tm k = quoteGenNF q opts defs None env tm k

export
Quote Term where
  quoteGen q opts defs env tm k = k tm

export
Quote Closure where
  quoteGen q opts defs env c k = quoteGen q opts defs env !(evalClosure defs c) k

quoteWithPiGen : {auto _ : Ref Ctxt Defs} ->
                 {bound, vars : _} ->
                 Ref QVar Int -> QuoteOpts answer -> Defs -> Bounds bound ->
                 Env Term vars -> NF vars ->
                 (Term (bound ++ vars) -> Core answer) -> Core answer
quoteWithPiGen q opts defs bound env (NBind fc n (Pi bfc c p ty) sc) k
    = do var <- genName (known Kqv)
         empty <- clearDefs defs
         scNF <- sc defs (toClosure defaultOpts env (Ref fc Bound var))
         quoteWithPiGen q opts defs (Add n var bound) env scNF $ \sc' =>
           do tyNF <- evalClosure empty ty
              quoteGenNF q opts empty bound env tyNF $ \ty' =>
                quotePi q opts empty bound env p $ \p' =>
                  k (Bind fc n (Pi bfc c p' ty') sc')
quoteWithPiGen q opts defs bound env (NErased fc t) k
    = quoteErased (quoteWithPiGen q opts defs bound env) t $ \t' => k (Erased fc t')
quoteWithPiGen q opts defs bound env tm k
    = do empty <- clearDefs defs
         quoteGenNF q opts empty bound env tm k

-- Quote back to a term, but only to find out how many Pi bindings there
-- are, don't reduce anything else
export
quoteWithPi : {auto c : Ref Ctxt Defs} ->
              {vars : Scope} ->
              Defs -> Env Term vars -> NF vars -> Core (Term vars)
quoteWithPi defs env tm
    = do q <- newRef QVar 0
         quoteWithPiGen q (MkQuoteOpts True False Whole) defs None env tm (\t => pure t)
