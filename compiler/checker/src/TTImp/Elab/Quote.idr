-- SPDX-License-Identifier: BSD-3-Clause
-- Copyright (c) 2020 Edwin Brady
module TTImp.Elab.Quote

import Core.Env
import Core.Metadata
import Core.Reflect
import Core.UnifyState

import Idris.REPL.Opts
import Idris.Syntax

import TTImp.Elab.Check
import TTImp.Reflect
import TTImp.TTImp

%default total

-- Collecting names and terms to let bind for unquoting
data Unq : Type where

-- Collect the escaped subterms in a term we're about to quote, and let bind
-- them first. Every list, option and wrapper a term holds terms in is walked
-- by a function of its own rather than by `traverse`, in the same order, so
-- that each recursive call is on a part of the term it was given and the
-- walk is total by its structure.
parameters {auto c : Ref Ctxt Defs}
           {auto q : Ref Unq (List (Name, FC, RawImp))}
           {auto u : Ref UST UState}

  getUnquote : RawImp -> Core RawImp

  getUnquotes : List RawImp -> Core (List RawImp)
  getUnquotes [] = pure []
  getUnquotes (t :: ts) = pure (!(getUnquote t) :: !(getUnquotes ts))

  getUnquoteMaybe : Maybe RawImp -> Core (Maybe RawImp)
  getUnquoteMaybe Nothing = pure Nothing
  getUnquoteMaybe (Just t) = map Just (getUnquote t)

  getUnquoteInfo : PiInfo RawImp -> Core (PiInfo RawImp)
  getUnquoteInfo Implicit = pure Implicit
  getUnquoteInfo Explicit = pure Explicit
  getUnquoteInfo AutoImplicit = pure AutoImplicit
  getUnquoteInfo (DefImplicit t) = map DefImplicit (getUnquote t)

  -- A binder's default value, then its type.
  getUnquoteBind : PiBindData RawImp -> Core (PiBindData RawImp)
  getUnquoteBind (MkPiBindData info ty) = MkPiBindData <$> getUnquoteInfo info <*> getUnquote ty

  getUnquoteClause : ImpClause -> Core ImpClause

  getUnquoteClauses : List ImpClause -> Core (List ImpClause)
  getUnquoteClauses [] = pure []
  getUnquoteClauses (cl :: cls) = pure (!(getUnquoteClause cl) :: !(getUnquoteClauses cls))

  getUnquoteClause (PatClause fc l r)
      = pure $ PatClause fc !(getUnquote l) !(getUnquote r)
  getUnquoteClause (WithClause fc l rig w prf flags cs)
      = pure $ WithClause
                 fc
                 !(getUnquote l)
                 rig
                 !(getUnquote w)
                 prf
                 flags
                 !(getUnquoteClauses cs)
  getUnquoteClause (ImpossibleClause fc l)
      = pure $ ImpossibleClause fc !(getUnquote l)

  getUnquoteUpdates : List IFieldUpdate -> Core (List IFieldUpdate)
  getUnquoteUpdates [] = pure []
  getUnquoteUpdates (ISetField p t :: upds)
      = pure (ISetField p !(getUnquote t) :: !(getUnquoteUpdates upds))
  getUnquoteUpdates (ISetFieldApp p t :: upds)
      = pure (ISetFieldApp p !(getUnquote t) :: !(getUnquoteUpdates upds))

  getUnquoteTys : List ImpTy -> Core (List ImpTy)
  getUnquoteTys [] = pure []
  getUnquoteTys (MkWithFCTyName fc n t :: tys)
      = pure (MkWithFCTyName fc n !(getUnquote t) :: !(getUnquoteTys tys))

  getUnquoteParam : ImpParameter -> Core ImpParameter
  getUnquoteParam (MkWithRigName rig n bind) = pure $ MkWithRigName rig n !(getUnquoteBind bind)

  getUnquoteParams : List ImpParameter -> Core (List ImpParameter)
  getUnquoteParams [] = pure []
  getUnquoteParams (p :: ps) = pure (!(getUnquoteParam p) :: !(getUnquoteParams ps))

  getUnquoteFields : List IField -> Core (List IField)
  getUnquoteFields [] = pure []
  getUnquoteFields (MkWithFCRigName fc rig n bind :: fields)
      = pure (MkWithFCRigName fc rig n !(getUnquoteBind bind) :: !(getUnquoteFields fields))

  getUnquoteRecord : ImpRecordData Name -> Core (ImpRecordData Name)
  getUnquoteRecord (MkImpRecord (MkWithName tyn params) (MkWithNameOpts con opts fields))
        -- unlike before, we are also unquoting the default value, maybe this is important?
      = pure $ MkImpRecord (MkWithName tyn !(getUnquoteParams params))
                           (MkWithNameOpts con opts !(getUnquoteFields fields))

  getUnquoteData : ImpData -> Core ImpData
  getUnquoteData (MkImpData fc n tc opts cs)
      = pure $ MkImpData fc n !(getUnquoteMaybe tc) opts !(getUnquoteTys cs)
  getUnquoteData (MkImpLater fc n tc)
      = pure $ MkImpLater fc n !(getUnquote tc)

  getUnquoteDecl : ImpDecl -> Core ImpDecl

  getUnquoteDecls : List ImpDecl -> Core (List ImpDecl)
  getUnquoteDecls [] = pure []
  getUnquoteDecls (d :: ds) = pure (!(getUnquoteDecl d) :: !(getUnquoteDecls ds))

  getUnquoteDecl (IClaim (MkFCVal fc (MkIClaimData rig v opts (MkWithFCTyName tfc tn ty))))
      = pure $ IClaim (MkFCVal fc (MkIClaimData rig v opts (MkWithFCTyName tfc tn !(getUnquote ty))))
  getUnquoteDecl (IData fc v mbt d)
      = pure $ IData fc v mbt !(getUnquoteData d)
  getUnquoteDecl (IDef fc v d)
      = pure $ IDef fc v !(getUnquoteClauses d)
  getUnquoteDecl (IParameters fc (p ::: ps) ds)
      = pure $ IParameters fc -- We also unquote default arguments here too
                           (!(getUnquoteParam p) ::: !(getUnquoteParams ps))
                           !(getUnquoteDecls ds)
  getUnquoteDecl (IRecord fc ns v mbt (MkFCVal rfc d))
      = pure $ IRecord fc ns v mbt (MkFCVal rfc !(getUnquoteRecord d))
  getUnquoteDecl (INamespace fc ns ds)
      = pure $ INamespace fc ns !(getUnquoteDecls ds)
  getUnquoteDecl (ITransform fc n l r)
      = pure $ ITransform fc n !(getUnquote l) !(getUnquote r)
  getUnquoteDecl d = pure d

  getUnquote (IPi fc rig p n arg ret)
      = pure $ IPi fc rig p n !(getUnquote arg) !(getUnquote ret)
  getUnquote (ILam fc rig p n arg sc)
      = pure $ ILam fc rig p n !(getUnquote arg) !(getUnquote sc)
  getUnquote (ILet fc lhsFC rig n ty val sc)
      = pure $ ILet fc lhsFC rig n !(getUnquote ty) !(getUnquote val) !(getUnquote sc)
  getUnquote (ICase fc opts sc ty cs)
      = pure $ ICase fc opts
                !(getUnquote sc) !(getUnquote ty)
                !(getUnquoteClauses cs)
  getUnquote (ILocal fc ds sc)
      = pure $ ILocal fc !(getUnquoteDecls ds) !(getUnquote sc)
  getUnquote (IUpdate fc ds sc)
      = pure $ IUpdate fc !(getUnquoteUpdates ds) !(getUnquote sc)
  getUnquote (IApp fc f a)
      = pure $ IApp fc !(getUnquote f) !(getUnquote a)
  getUnquote (IAutoApp fc f a)
      = pure $ IAutoApp fc !(getUnquote f) !(getUnquote a)
  getUnquote (INamedApp fc f n a)
      = pure $ INamedApp fc !(getUnquote f) n !(getUnquote a)
  getUnquote (IWithApp fc f a)
      = pure $ IWithApp fc !(getUnquote f) !(getUnquote a)
  getUnquote (IAlternative fc at as)
      = pure $ IAlternative fc at !(getUnquotes as)
  getUnquote (ITypeOrValue fc (PairOf l r))
      = pure $ ITypeOrValue fc (PairOf !(getUnquote l) !(getUnquote r))
  getUnquote (ITypeOrValue fc UnitOf)
      = pure $ ITypeOrValue fc UnitOf
  getUnquote (ITypeOrValue fc (DPairOf opFC nameFC n r))
      = pure $ ITypeOrValue fc (DPairOf opFC nameFC n !(getUnquote r))
  getUnquote (IRewrite fc f a)
      = pure $ IRewrite fc !(getUnquote f) !(getUnquote a)
  getUnquote (ICoerced fc t)
      = pure $ ICoerced fc !(getUnquote t)
  getUnquote (IBindHere fc m t)
      = pure $ IBindHere fc m !(getUnquote t)
  getUnquote (IAs fc nameFC side nm t)
      = pure $ IAs fc nameFC side nm !(getUnquote t)
  getUnquote (IMustUnify fc r t)
      = pure $ IMustUnify fc r !(getUnquote t)
  getUnquote (IDelayed fc r t)
      = pure $ IDelayed fc r !(getUnquote t)
  getUnquote (IDelay fc t)
      = pure $ IDelay fc !(getUnquote t)
  getUnquote (IForce fc t)
      = pure $ IForce fc !(getUnquote t)
  getUnquote (IQuote fc t)
      = pure $ IQuote fc !(getUnquote t)
  getUnquote (IUnquote fc tm)
      = do qv <- genVarName (known Kq)
           update Unq ((qv, fc, tm) ::)
           pure (IUnquote fc (IVar fc qv)) -- turned into just qv when reflecting
  getUnquote tm = pure tm

onLHS : ElabMode -> Bool
onLHS (InLHS _) = True
onLHS _ = False

-- Quoting elaborates each escaped term and checks the quoted term against
-- the type it is expected at, and elaboration runs what types compute,
-- which need not end, since Idris's theory is not strongly normalizing. So
-- what follows is covering.
%default covering

bindUnqs : {vars : _} ->
           {auto c : Ref Ctxt Defs} ->
           {auto m : Ref MD Metadata} ->
           {auto u : Ref UST UState} ->
           {auto dl : Ref DLY DelayedElabs} ->
           {auto e : Ref EST (EState vars)} ->
           {auto s : Ref Syn SyntaxInfo} ->
           {auto o : Ref ROpts REPLOpts} ->
           List (Name, FC, RawImp) ->
           RigCount -> ElabInfo -> NestedNames vars -> Env Term vars ->
           Term vars ->
           Core (Term vars)
bindUnqs [] _ _ _ _ tm = pure tm
bindUnqs ((qvar, fc, esctm) :: qs) rig elabinfo nest env tm
    = do defs <- get Ctxt
         Just (idx, gdef) <- lookupCtxtExactI (reflectionttimp KTTImp) (gamma defs)
              | _ => throw (UndefinedName fc (reflectionttimp KTTImp))
         (escv, escty) <- check rig elabinfo nest env esctm
                                (Just (gnf env (Ref fc (TyCon 0)
                                           (Resolved idx))))
         sc <- bindUnqs qs rig elabinfo nest env tm
         pure (Bind fc qvar (Let fc (rigMult top rig) escv !(getTerm escty))
                    (refToLocal qvar qvar sc))

export
checkQuote : {vars : _} ->
             {auto c : Ref Ctxt Defs} ->
             {auto m : Ref MD Metadata} ->
             {auto u : Ref UST UState} ->
             {auto dl : Ref DLY DelayedElabs} ->
             {auto e : Ref EST (EState vars)} ->
             {auto s : Ref Syn SyntaxInfo} ->
             {auto o : Ref ROpts REPLOpts} ->
             RigCount -> ElabInfo ->
             NestedNames vars -> Env Term vars ->
             FC -> RawImp -> Maybe (Glued vars) ->
             Core (Term vars, Glued vars)
checkQuote rig elabinfo nest env fc tm exp
    = do defs <- get Ctxt
         q <- newRef Unq []
         tm' <- getUnquote tm
         qtm <- reflect fc defs (onLHS (elabMode elabinfo)) env tm'
         unqs <- get Unq
         qty <- getCon fc defs (reflectionttimp KTTImp)
         qtm <- bindUnqs unqs rig elabinfo nest env qtm
         fullqtm <- normalise defs env qtm
         checkExp rig elabinfo env fc fullqtm (gnf env qty) exp

export
checkQuoteName : {vars : _} ->
                 {auto c : Ref Ctxt Defs} ->
                 {auto u : Ref UST UState} ->
                 RigCount -> ElabInfo ->
                 NestedNames vars -> Env Term vars ->
                 FC -> Name -> Maybe (Glued vars) ->
                 Core (Term vars, Glued vars)
checkQuoteName rig elabinfo nest env fc n exp
    = do defs <- get Ctxt
         qnm <- reflect fc defs (onLHS (elabMode elabinfo)) env n
         qty <- getCon fc defs (reflectiontt KName)
         checkExp rig elabinfo env fc qnm (gnf env qty) exp

export
checkQuoteDecl : {vars : _} ->
                 {auto c : Ref Ctxt Defs} ->
                 {auto m : Ref MD Metadata} ->
                 {auto u : Ref UST UState} ->
                 {auto dl : Ref DLY DelayedElabs} ->
                 {auto e : Ref EST (EState vars)} ->
                 {auto s : Ref Syn SyntaxInfo} ->
                 {auto o : Ref ROpts REPLOpts} ->
                 RigCount -> ElabInfo ->
                 NestedNames vars -> Env Term vars ->
                 FC -> List ImpDecl -> Maybe (Glued vars) ->
                 Core (Term vars, Glued vars)
checkQuoteDecl rig elabinfo nest env fc ds exp
    = do defs <- get Ctxt
         q <- newRef Unq []
         ds' <- getUnquoteDecls ds
         qds <- reflect fc defs (onLHS (elabMode elabinfo)) env ds'
         unqs <- get Unq
         qd <- getCon fc defs (reflectionttimp KDecl)
         qty <- appCon fc defs (basics KList) [qd]
         checkExp rig elabinfo env fc
                  !(bindUnqs unqs rig elabinfo nest env qds)
                  (gnf env qty) exp
