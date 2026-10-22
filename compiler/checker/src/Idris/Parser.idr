-- SPDX-License-Identifier: BSD-3-Clause
-- Copyright (c) 2020 Edwin Brady
module Idris.Parser

import Core.Metadata
import Idris.Syntax
import Idris.Syntax.Tree
import public Parser.Source
import TTImp.TTImp

import public Libraries.Text.Parser
import Data.Either
import Libraries.Data.IMaybe
import Data.List.Quantifiers
import Data.List1
import Data.Maybe
import Data.Nat
import Data.String
import Libraries.Utils.String
import Libraries.Data.WithDefault

import Idris.Parser.Let

%default covering

fcBounds : OriginDesc => Rule a -> Rule (WithFC a)
fcBounds a = (.withFC) <$> bounds a

decorate : {0 a : Type} -> OriginDesc -> Decoration -> Rule a -> Rule a
decorate fname decor rule = do
  res <- bounds rule
  actD (decorationFromBounded fname decor res)
  pure res.val

dependentDecorate : {0 a : Type} -> OriginDesc -> Rule a -> (a -> Decoration) -> Rule a
dependentDecorate fname rule decor = do
  res <- bounds rule
  actD (decorationFromBounded fname (decor res.val) res)
  pure res.val

decoratedKeyword : OriginDesc -> Keyword -> Rule ()
decoratedKeyword fname kwd = decorate fname Keyword (keyword kwd)

decorateKeywords : {0 a : Type} -> OriginDesc -> List (WithBounds a) -> EmptyRule ()
decorateKeywords fname xs
  = actD (concatMap (decorationFromBounded fname Keyword) xs)

decoratedPragma : OriginDesc -> KwPragma -> Rule ()
decoratedPragma fname prg = decorate fname Keyword (pragma fname prg)

decoratedSymbol : OriginDesc -> Reserved -> Rule ()
decoratedSymbol fname smb = decorate fname Keyword (symbol smb)

decoratedNamespacedSymbol : OriginDesc -> (plain, dotted : Reserved) -> Rule (Maybe Namespace)
decoratedNamespacedSymbol fname plain dotted =
  decorate fname Keyword $ namespacedSymbol plain dotted

parens : {b : _} -> OriginDesc -> BRule b a -> Rule a
parens fname p
  = pure id <* decoratedSymbol fname SymParen
            <*> p
            <* decoratedSymbol fname SymParenClose

curly : {b : _} -> OriginDesc -> BRule b a -> Rule a
curly fname p
  = pure id <* decoratedSymbol fname SymBrace
            <*> p
            <* decoratedSymbol fname SymBraceClose

decoratedDataTypeName : OriginDesc -> Rule Name
decoratedDataTypeName fname = decorate fname Typ dataTypeName

decoratedDataConstructorName : OriginDesc -> Rule Name
decoratedDataConstructorName fname = decorate fname Data dataConstructorName

decoratedSimpleBinderUName : OriginDesc -> Rule Name
decoratedSimpleBinderUName fname = decorate fname Bound userName

decoratedSimpleNamedArg : OriginDesc -> Rule Ident
decoratedSimpleNamedArg fname
  = decorate fname Bound unqualifiedName
  <|> parens fname (decorate fname Bound unqualifiedOperatorName)

-- Forward declare since they're used in the parser
topDecl : OriginDesc -> IndentInfo -> Rule (Id FDecl)

-- Some context for the parser
public export
record ParseOpts where
  constructor MkParseOpts
  eqOK : Bool -- = operator is parseable
  withOK : Bool -- = with applications are parseable

peq : ParseOpts -> ParseOpts
peq = { eqOK := True }

pnoeq : ParseOpts -> ParseOpts
pnoeq = { eqOK := False }

export
pdef : ParseOpts
pdef = MkParseOpts {eqOK = True, withOK = True}

pnowith : ParseOpts
pnowith = MkParseOpts {eqOK = True, withOK = False}

export
plhs : ParseOpts
plhs = MkParseOpts {eqOK = False, withOK = False}

%hide Prelude.(>>)
%hide Prelude.(>>=)
%hide Core.Core.(>>)
%hide Core.Core.(>>=)
%hide Prelude.pure
%hide Core.Core.pure
%hide Prelude.(<*>)
%hide Core.Core.(<*>)

atom : OriginDesc -> Rule (Id FTerm)
atom fname
    = do x <- bounds $ decorate fname Typ $ exactIdent KType
         node (TmType (boundToFC fname x))
  <|> do x <- bounds $ name
         node (TmRef (boundToFC fname x) x.val)
  <|> do x <- bounds $ dependentDecorate fname constant $ \c =>
                       if isPrimType c
                       then Typ
                       else Data
         node (TmPrimVal (boundToFC fname x) x.val)
  <|> do x <- bounds $ decoratedSymbol fname SymUnderscore
         node (TmImplicit (boundToFC fname x))
  <|> do x <- bounds $ symbol SymQuestion
         node (TmInfer (boundToFC fname x))
  <|> do x <- bounds $ holeName
         node (TmHole (boundToFC fname x) False x.val)
  <|> do x <- bounds $ decorate fname Data $ pragma fname KwMkWorld
         node (TmPrimVal (boundToFC fname x) WorldVal)
  <|> do x <- bounds $ decorate fname Typ  $ pragma fname KwWorld
         node (TmPrimVal (boundToFC fname x) $ PrT WorldType)
  <|> do x <- bounds $ decoratedPragma fname KwSearch
         node (TmSearch (boundToFC fname x))

whereBlock : OriginDesc -> Int -> Rule (List (Id FDecl))
whereBlock fname col
    = do decoratedKeyword fname KwWhere
         blockAfter col (topDecl fname)

-- Expect a keyword, but if we get anything else it's a fatal error
commitKeyword : OriginDesc -> IndentInfo -> Keyword -> Rule ()
commitKeyword fname indents req
    = do mustContinue indents (Just (keywordText req))
         decoratedKeyword fname req
          <|> the (Rule ()) (fatalError ("Expected '" ++ keywordText req ++ "'"))
         mustContinue indents Nothing

commitSymbol : OriginDesc -> Reserved -> Rule ()
commitSymbol fname req
    = decoratedSymbol fname req
       <|> fatalError ("Expected '" ++ reservedText req ++ "'")

continueWithDecorated : OriginDesc -> IndentInfo -> Reserved -> Rule ()
continueWithDecorated fname indents req
    = mustContinue indents (Just (reservedText req)) *> decoratedSymbol fname req


continueWith : IndentInfo -> Reserved -> Rule ()
continueWith indents req
    = mustContinue indents (Just (reservedText req)) *> symbol req

iOperator : Rule OpStr
iOperator
    = OpSymbols <$> operator
  <|> Backticked <$> (symbol SymBackquote *> name <* symbol SymBackquote)

data ArgType
    = UnnamedExpArg (Id FTerm)
    | UnnamedAutoArg (Id FTerm)
    | NamedArg Name (Id FTerm)
    | WithArg (Id FTerm)

-- A function applied to its arguments in turn, each application where the
-- whole is.
applied : FC -> Id FTerm -> List ArgType -> EmptyRule (Id FTerm)
applied fc f args = build (foldlM step f args)
  where
    step : Id FTerm -> ArgType -> Build (Id FTerm)
    step g (UnnamedExpArg exp) = make (TmApp fc g exp)
    step g (UnnamedAutoArg imp) = make (TmAutoApp fc g imp)
    step g (NamedArg n imp) = make (TmNamedApp fc g n imp)
    step g (WithArg exp) = make (TmWithApp fc g exp)

-- A clause's left side with its `with` arguments applied.
withApplied : (Id FTerm, List (FC, Id FTerm)) -> EmptyRule (Id FTerm)
withApplied (f, args) = build (foldlM (\g, (fc, a) => make (TmWithApp fc g a)) f args)

-- The left side of a `with` clause written `_`: its parent's, every location
-- in it where the `_` is.
relocated : FC -> (Id FTerm, List (FC, Id FTerm)) -> EmptyRule (Id FTerm, List (FC, Id FTerm))
relocated vfc (f, args)
    = do f' <- node (TmRelocated vfc f)
         args' <- build (traverse (\(fc, a) => MkPair fc <$> make (TmRelocated vfc a)) args)
         pure (f', args')

-- A binder of several names, with its quantity and their type.
multiBinder : (RigCount, List1 (WithFC Name), Id FTerm) -> EmptyRule (Id FNames)
multiBinder (rig, ns, ty) = node (BnNames rig ns ty)

export
debugString : OriginDesc -> Rule (Id FTerm)
debugString fname = do
  di <- debugInfo
  node $ TmPrimVal (boundToFC' fname (snd di)) $ Str $ case fst di of
    DebugLoc =>
      let bnds = snd di in
      joinBy ", "
      [ "File \{show fname}"
      , "line \{show (startLine bnds)}"
      , "characters \{show (startCol bnds)}\{
           ifThenElse (startLine bnds == endLine bnds)
            ("-\{show (endCol bnds)}")
            ""
        }"
      ]
    DebugFile => "\{show fname}"
    DebugLine => "\{show (startLine (snd di))}"
    DebugCol => "\{show (startCol (snd di))}"

totalityOpt : OriginDesc -> Rule TotalReq
totalityOpt fname
    = (decoratedKeyword fname KwPartial $> PartialOK)
  <|> (decoratedKeyword fname KwTotal $> Total)
  <|> (decoratedKeyword fname KwCovering $> CoveringOnly)

fnOpt : OriginDesc -> Rule (Id FOpt)
fnOpt fname
      = do x <- totalityOpt fname
           node (OpFn (Totality x))

mutual
  appExpr : ParseOpts -> OriginDesc -> IndentInfo -> Rule (Id FTerm)
  appExpr q fname indents
      = case_ fname indents
    <|> doBlock fname indents
    <|> lam fname indents
    <|> lazy fname indents
    <|> if_ fname indents
    <|> with_ fname indents
    <|> do b <- bounds (MkPair <$> simpleExpr fname indents <*> many (argExpr q fname indents))
           (f, args) <- pure b.val
           applied (boundToFC fname b) f (concat args)
    <|> do b <- fcBounds (MkPair <$> fcBounds iOperator <*> expr pdef fname indents)
           (op, arg) <- pure b.val
           node (TmPrefixOp b.fc op arg)
    <|> fail "Expected 'case', 'if', 'do', application or operator expression"

  argExpr : ParseOpts -> OriginDesc -> IndentInfo -> Rule (List ArgType)
  argExpr q fname indents
      = do continue indents
           arg <- simpleExpr fname indents
           build (bracketHole arg)
           pure [UnnamedExpArg arg]
    <|> do continue indents
           braceArgs fname indents
    <|> if withOK q
           then do continue indents
                   decoratedSymbol fname SymBar
                   arg <- expr ({withOK := False} q) fname indents
                   pure [WithArg arg]
           else fail "| not allowed here"
    where
      underscore : FC -> EmptyRule ArgType
      underscore fc = NamedArg (UN Underscore) <$> node (TmImplicit fc)

      braceArgs : OriginDesc -> IndentInfo -> Rule (List ArgType)
      braceArgs fname indents
        = do start <- bounds (decoratedSymbol fname SymBrace)
             mustWork $ do
               list <- sepBy (decoratedSymbol fname SymComma)
                        $ do x <- bounds (UN . Basic <$> decoratedSimpleNamedArg fname)
                             let fc = boundToFC fname x
                             (do tm <- decoratedSymbol fname SymEquals *> typeExpr pdef fname indents
                                 pure (NamedArg x.val tm))
                               <|> (NamedArg x.val <$> node (TmRef fc x.val))
               matchAny <- option [] (if isCons list then
                                         do decoratedSymbol fname SymComma
                                            x <- bounds (decoratedSymbol fname SymUnderscore)
                                            u <- underscore (boundToFC fname x)
                                            pure [u]
                                      else fail "non-empty list required")
               end <- bounds (decoratedSymbol fname SymBraceClose)
               matchAny <- if isNil list
                              then do u <- underscore (boundToFC fname (mergeBounds start end))
                                      pure [u]
                              else pure matchAny
               pure $ matchAny ++ list

        <|> do decoratedSymbol fname SymAtBrace
               commit
               tm <- typeExpr pdef fname indents
               decoratedSymbol fname SymBraceClose
               pure [UnnamedAutoArg tm]

  with_ : OriginDesc -> IndentInfo -> Rule (Id FTerm)
  with_ fname indents
      = do b <- bounds (do decoratedKeyword fname KwWith
                           commit
                           ns <- singleName <|> nameList
                           end <- location
                           rhs <- expr pdef fname indents
                           pure (ns, rhs))
           (ns, rhs) <- pure b.val
           node (TmWithNames (boundToFC fname b) ns rhs)
    where
      singleName : Rule (List (FC, Name))
      singleName = do
        n <- bounds name
        pure [(boundToFC fname n, n.val)]

      nameList : Rule (List (FC, Name))
      nameList = do
        decoratedSymbol fname SymBracket
        commit
        ns <- sepBy1 (decoratedSymbol fname SymComma) (bounds name)
        decoratedSymbol fname SymBracketClose
        pure (map (\ n => (boundToFC fname n, n.val)) $ forget ns)

  -- The different kinds of operator bindings `x : ty` for typebind
  -- x <- e and x : ty <- e for autobind
  opBinderTypes : OriginDesc -> IndentInfo -> WithBounds (Id FTerm) -> Rule (OperatorLHSInfo (Id FTerm))
  opBinderTypes fname indents boundName =
           do decoratedSymbol fname SymColon
              ty <- typeExpr pdef fname indents
              decoratedSymbol fname SymLeftArrow
              exp <- expr pdef fname indents
              pure (BindExplicitType boundName.val ty exp)
       <|> do decoratedSymbol fname SymLeftArrow
              exp <- expr pdef fname indents
              pure (BindExpr boundName.val exp)
       <|> do decoratedSymbol fname SymColon
              ty <- typeExpr pdef fname indents
              pure (BindType boundName.val ty)

  opBinder : OriginDesc -> IndentInfo -> Rule (OperatorLHSInfo (Id FTerm))
  opBinder fname indents
      = do boundName <- bounds (expr plhs fname indents)
           opBinderTypes fname indents boundName

  autobindOp : ParseOpts -> OriginDesc -> IndentInfo -> Rule (Id FTerm)
  autobindOp q fname indents
      = do b <- fcBounds $ do
             binder <- fcBounds $ parens fname (opBinder fname indents)
             continue indents
             op <- fcBounds iOperator
             commit
             e <- expr q fname indents
             pure (binder, op, e)
           node (TmOp b.fc (fst b.val) (fst (snd b.val)) (snd (snd b.val)))

  opExprBase : ParseOpts -> OriginDesc -> IndentInfo -> Rule (Id FTerm)
  opExprBase q fname indents
      = do l <- bounds (appExpr q fname indents)
           (if eqOK q
               then do r <- bounds (continue indents
                                *> decoratedSymbol fname SymEquals
                                *> opExprBase q fname indents)
                       node $
                         let fc = boundToFC fname (mergeBounds l r)
                             opFC = virtualiseFC fc -- already been highlighted: we don't care
                         in TmOp fc (map NoBinder l.withFC)
                                    (MkFCVal opFC (OpSymbols $ knownUN KEquals))
                                    r.val
               else fail "= not allowed")
             <|>
             (do b <- bounds $ do
                        continue indents
                        op <- fcBounds iOperator
                        let root = case op.val of
                                        OpSymbols n => knownRoot n
                                        Backticked _ => Nothing
                        e <- case root of
                               Just KDollar => typeExpr q fname indents
                               _ => expr q fname indents
                        pure (op, e)
                 (op, r) <- pure b.val
                 let fc = boundToFC fname (mergeBounds l b)
                 node (TmOp fc (map NoBinder l.withFC) op r))
               <|> pure l.val

  opExpr : ParseOpts -> OriginDesc -> IndentInfo -> Rule (Id FTerm)
  opExpr q fname indents = autobindOp q fname indents
                       <|> opExprBase q fname indents

  dpairType : OriginDesc -> WithBounds t -> IndentInfo -> Rule (Id FTerm)
  dpairType fname start indents
      = do loc <- bounds (do x <- decoratedSimpleBinderUName fname
                             decoratedSymbol fname SymColon
                             ty <- typeExpr pdef fname indents
                             pure (x, ty))
           (x, ty) <- pure loc.val
           op <- bounds (symbol SymStarStar)
           rest <- bounds (nestedDpair fname loc indents <|> typeExpr pdef fname indents)
           var <- node (TmRef (boundToFC fname loc) x)
           node (TmDPair (boundToFC fname (mergeBounds start rest))
                         (boundToFC fname op)
                         var
                         ty
                         rest.val)

  nestedDpair : OriginDesc -> WithBounds t -> IndentInfo -> Rule (Id FTerm)
  nestedDpair fname start indents
      = dpairType fname start indents
    <|> do l <- expr pdef fname indents
           loc <- bounds (symbol SymStarStar)
           rest <- bounds (nestedDpair fname loc indents <|> expr pdef fname indents)
           imp <- node (TmImplicit (boundToFC fname (mergeBounds start rest)))
           node (TmDPair (boundToFC fname (mergeBounds start rest))
                         (boundToFC fname loc)
                         l
                         imp
                         rest.val)

  bracketedExpr : OriginDesc -> WithBounds t -> IndentInfo -> Rule (Id FTerm)
  bracketedExpr fname s indents
      -- left section. This may also be a prefix operator, but we'll sort
      -- that out when desugaring: if the operator is infix, treat it as a
      -- section otherwise treat it as prefix
      = do b <- bounds (do op <- fcBounds iOperator
                           e <- expr pdef fname indents
                           continueWithDecorated fname indents SymParenClose
                           pure (op, e))
           (op, e) <- pure b.val
           actD [(toNonEmptyFC $ boundToFC fname s, Keyword, Nothing)]
           let fc = boundToFC fname (mergeBounds s b)
           node (TmSectionL fc op e)
    <|> do  -- (.y.z)  -- section of projection (chain)
           b <- bounds $ forget <$> some (bounds postfixProj)
           decoratedSymbol fname SymParenClose
           actD [(toNonEmptyFC $ boundToFC fname s, Keyword, Nothing)]
           let projs = map (\ proj => (boundToFC fname proj, proj.val)) b.val
           node $ TmPostfixAppPartial (boundToFC fname b) projs
      -- unit type/value
    <|> do b <- bounds (continueWith indents SymParenClose)
           node (TmUnit (boundToFC fname (mergeBounds s b)))
      -- dependent pairs with type annotation (so, the type form)
    <|> do dpairType fname s indents <* (decorate fname Typ $ symbol SymParenClose)
                                     <* actD [(toNonEmptyFC $ boundToFC fname s, Typ, Nothing)]
    <|> do e <- bounds (typeExpr pdef fname indents)
           -- dependent pairs with no type annotation
           (do loc <- bounds (symbol SymStarStar)
               rest <- bounds ((nestedDpair fname loc indents <|> expr pdef fname indents) <* symbol SymParenClose)
               imp <- node (TmImplicit (boundToFC fname (mergeBounds s rest)))
               node (TmDPair (boundToFC fname (mergeBounds s rest))
                             (boundToFC fname loc)
                             e.val
                             imp
                             rest.val)) <|>
             -- right sections
             ((do op <- bounds (fcBounds iOperator <* decoratedSymbol fname SymParenClose)
                  actD [(toNonEmptyFC $ boundToFC fname s, Keyword, Nothing)]
                  let fc = boundToFC fname (mergeBounds s op)
                  node (TmSectionR fc e.val op.val)
               <|>
              -- all the other bracketed expressions
              tuple fname s indents e.val))
    <|> do here <- location
           let fc = MkFC fname here here
           -- the section's variable, its lambda's and its tuple's
           var <- node (TmRef fc (MN (known K__leftTupleSection) 0))
           ts <- bounds (nonEmptyTuple fname s indents var)
           inf <- node (TmInfer fc)
           node (TmLam fc top Explicit var inf ts.val)

  getInitRange : List (WithBounds (Id FTerm)) -> EmptyRule (Id FTerm, Maybe (Id FTerm))
  getInitRange [x] = pure (x.val, Nothing)
  getInitRange [x,y] = pure (x.val, Just y.val)
  getInitRange _ = fatalError "Invalid list range syntax"

  listRange : OriginDesc -> WithBounds t -> IndentInfo -> List (WithBounds (Id FTerm)) -> Rule (Id FTerm)
  listRange fname s indents xs
      = do b <- bounds (decoratedSymbol fname SymBracketClose)
           let fc = boundToFC fname (mergeBounds s b)
           rstate <- getInitRange xs
           decorateKeywords fname xs
           node (TmRangeStream fc (fst rstate) (snd rstate))
    <|> do y <- bounds (expr pdef fname indents <* decoratedSymbol fname SymBracketClose)
           let fc = boundToFC fname (mergeBounds s y)
           rstate <- getInitRange xs
           decorateKeywords fname xs
           node (TmRange fc (fst rstate) (snd rstate) y.val)

  listExpr : OriginDesc -> WithBounds () -> IndentInfo -> Rule (Id FTerm)
  listExpr fname s indents
      = do b <- bounds (do ret <- expr pnowith fname indents
                           decoratedSymbol fname SymBar
                           conds <- sepBy1 (decoratedSymbol fname SymComma) (doAct fname indents)
                           decoratedSymbol fname SymBracketClose
                           pure (ret, conds))
           (ret, conds) <- pure b.val
           node (TmComprehension (boundToFC fname (mergeBounds s b)) ret (concat conds))
    <|> do xs <- option [] $ do
                     hd <- expr pdef fname indents
                     tl <- many $ do b <- bounds (symbol SymComma)
                                     x <- mustWork $ expr pdef fname indents
                                     pure (x <$ b)
                     pure ((hd <$ s) :: tl)
           (do decoratedSymbol fname SymDotDot
               listRange fname s indents xs)
             <|> (do b <- bounds (symbol SymBracketClose)
                     node $
                       let fc = boundToFC fname (mergeBounds s b)
                           nilFC = if null xs then fc else boundToFC fname b
                       in TmList fc nilFC (map (\ t => (boundToFC fname t, t.val)) xs))

  snocListExpr : OriginDesc -> WithBounds () -> IndentInfo -> Rule (Id FTerm)
  snocListExpr fname s indents
      = {- TODO: comprehension -}
        do mHeadTail <- optional $ do
             hd <- many $ do x <- expr pdef fname indents
                             b <- bounds (symbol SymComma)
                             pure (x <$ b)
             tl <- expr pdef fname indents
             pure (hd, tl)
           {- TODO: reverse ranges -}
           b <- bounds (symbol SymBracketClose)
           node $
             let xs : SnocList (WithBounds (Id FTerm))
                    = case mHeadTail of
                        Nothing      => [<]
                        Just (hd,tl) => ([<] <>< hd) :< (tl <$ b)
                 fc = boundToFC fname (mergeBounds s b)
                 nilFC = ifThenElse (null xs) fc (boundToFC fname s)
             in TmSnocList fc nilFC (map (\ t => (boundToFC fname t, t.val)) xs) --)

  -- A tuple with its first component `e`, or a section of one: each
  -- component left out is a variable the section binds, each pair is where
  -- its comma is.
  nonEmptyTuple : OriginDesc -> WithBounds t -> IndentInfo -> Id FTerm -> Rule (Id FTerm)
  nonEmptyTuple fname s indents e
      = do vals <- some $ do b <- bounds (symbol SymComma)
                             exp <- optional (typeExpr pdef fname indents)
                             pure (boundToFC fname b, exp)
           end <- continueWithDecorated fname indents SymParenClose
           actD [(toNonEmptyFC (boundToFC fname s), Keyword, Nothing)]
           comps <- build (traverse component (numbered vals))
           let terms = map (either id id . snd) comps
           let lefts = e :: init terms
           let fcs = forget (map fst comps)
           pairs <- build (foldlM (\acc, (f, l) => make (TmPair f l acc))
                                  (last terms) (reverse (zip fcs lefts)))
           let vars = mapMaybe (\(fc, c) => MkPair fc <$> getRight c) (forget comps)
           infs <- build (traverse (\(fc, v) => (\i => (fc, v, i)) <$> make (TmInfer (virtualiseFC fc)))
                                   vars)
           build (foldlM (\acc, (fc, v, i) => make (TmLam (virtualiseFC fc) top Explicit v i acc))
                         pairs (reverse infs))
    where
      -- The components after the first, each left out one numbered among
      -- those left out.
      numberedFrom : Int -> List (FC, Maybe (Id FTerm)) -> List (FC, Either (Id FTerm) Int)
      numberedFrom i [] = []
      numberedFrom i ((fc, Just c) :: cs) = (fc, Left c) :: numberedFrom i cs
      numberedFrom i ((fc, Nothing) :: cs) = (fc, Right i) :: numberedFrom (i + 1) cs

      numbered : List1 (FC, Maybe (Id FTerm)) -> List1 (FC, Either (Id FTerm) Int)
      numbered ((fc, Just c) ::: cs) = (fc, Left c) ::: numberedFrom 0 cs
      numbered ((fc, Nothing) ::: cs) = (fc, Right 0) ::: numberedFrom 1 cs

      -- A component: as written, or the variable it is left out for.
      component : (FC, Either (Id FTerm) Int) -> Build (FC, Either (Id FTerm) (Id FTerm))
      component (fc, c)
          = MkPair fc <$> traverse (\i => make (TmRef fc (MN (known K__infixTupleSection) i))) c

  -- A pair, dependent pair, or just a single expression
  tuple : OriginDesc -> WithBounds t -> IndentInfo -> Id FTerm -> Rule (Id FTerm)
  tuple fname s indents e
     =   nonEmptyTuple fname s indents e
     <|> do end <- bounds (continueWithDecorated fname indents SymParenClose)
            actD [(toNonEmptyFC $ boundToFC fname s, Keyword, Nothing)]
            node (TmBracketed (boundToFC fname (mergeBounds s end)) e)

  simpleExpr : OriginDesc -> IndentInfo -> Rule (Id FTerm)
  simpleExpr fname indents
    = do  -- x.y.z
          b <- bounds (do root <- simplerExpr fname indents
                          projs <- many (bounds postfixProj)
                          pure (root, projs))
          (root, projs) <- pure b.val
          let projs = map (\ proj => (boundToFC fname proj, proj.val)) projs
          case projs of
            [] => pure root
            _  => node (TmPostfixApp (boundToFC fname b) root projs)
    <|> debugString fname
    <|> do b <- bounds (forget <$> some (bounds postfixProj))
           node $ let projs = map (\ proj => (boundToFC fname proj, proj.val)) b.val in
                  TmPostfixAppPartial (boundToFC fname b) projs

  simplerExpr : OriginDesc -> IndentInfo -> Rule (Id FTerm)
  simplerExpr fname indents
      = do b <- bounds (do x <- bounds (decoratedSimpleBinderUName fname)
                           decoratedSymbol fname SymAt
                           commit
                           expr <- simpleExpr fname indents
                           pure (x, expr))
           (x, expr) <- pure b.val
           node (TmAs (boundToFC fname b) (boundToFC fname x) x.val expr)
    <|> do b <- bounds $ do
                  mns <- decoratedNamespacedSymbol fname SymIdiom SymDotIdiom
                  t   <- expr pdef fname indents
                  decoratedSymbol fname SymIdiomClose
                  pure (t, mns)
           node (TmIdiom (boundToFC fname b) (snd b.val) (fst b.val))
    <|> atom fname
    <|> record_ fname indents
    <|> singlelineStr pdef fname indents
    <|> multilineStr pdef fname indents
    <|> do b <- bounds $ do
                  decoratedSymbol fname SymDotParen
                  commit
                  t <- typeExpr pdef fname indents
                  decoratedSymbol fname SymParenClose
                  pure t
           node (TmDotted (boundToFC fname b) b.val)
    <|> do b <- bounds $ do
                  decoratedSymbol fname SymQuoteParen
                  t <- typeExpr pdef fname indents
                  decoratedSymbol fname SymParenClose
                  pure t
           node (TmQuote (boundToFC fname b) b.val)
    <|> do b <- bounds $ do
                  decoratedSymbol fname SymQuoteBrace
                  t <- name
                  decoratedSymbol fname SymBraceClose
                  pure t
           node (TmQuoteName (boundToFC fname b) b.val)
    <|> do b <- bounds $ do
                  decoratedSymbol fname SymQuoteBracket
                  ts <- nonEmptyBlock (topDecl fname)
                  decoratedSymbol fname SymBracketClose
                  pure ts
           node (TmQuoteDecl (boundToFC fname b) (forget b.val))
    <|> do b <- bounds (decoratedSymbol fname SymTilde *> simplerExpr fname indents)
           node (TmUnquote (boundToFC fname b) b.val)
    <|> do start <- bounds (symbol SymParen)
           bracketedExpr fname start indents
    <|> do start <- bounds (symbol SymSnocBracket)
           snocListExpr fname start indents
    <|> do start <- bounds (symbol SymListBracket <|> symbol SymBracket)
           listExpr fname start indents
    <|> do b <- bounds (decoratedSymbol fname SymBang *> simpleExpr fname indents)
           node (TmBang (virtualiseFC $ boundToFC fname b) b.val)
    <|> do b <- bounds $ do decoratedPragma fname KwLogging
                            topic <- optional (split (('.') ==) <$> simpleStr)
                            lvl   <- intLit
                            e     <- expr pdef fname indents
                            pure (MkPair (mkLogLevel' topic (integerToNat lvl)) e)
           (lvl, e) <- pure b.val
           node (TmUnifyLog (boundToFC fname b) lvl e)
    <|> withWarning "DEPRECATED: trailing lambda. Use a $ or parens"
        (lam fname indents)

  multiplicity : OriginDesc -> EmptyRule RigCount
  multiplicity fname
      = case !(optional $ decorate fname Keyword intLit) of
          (Just 0) => pure erased
          (Just 1) => pure linear
          Nothing => pure top
          _ => fail "Invalid multiplicity (must be 0 or 1)"

  bindList : OriginDesc -> IndentInfo ->
             Rule (List (RigCount, WithBounds (Id FTerm), Id FTerm, PiInfo (Id FTerm)))
  bindList fname indents
      = forget <$> sepBy1 (decoratedSymbol fname SymComma) (explicitBind <|> implicitBind)
    where
      explicitBind : Rule (RigCount, WithBounds (Id FTerm), Id FTerm, PiInfo (Id FTerm))
      explicitBind = do
        rig <- multiplicity fname
        pat <- bounds (simpleExpr fname indents)
        ty <- (decoratedSymbol fname SymColon *> opExpr pdef fname indents)
                <|> node (TmInfer (boundToFC fname pat))
        pure (rig, pat, ty, Explicit)

      implicitBind : Rule (RigCount, WithBounds (Id FTerm), Id FTerm, PiInfo (Id FTerm))
      implicitBind = curly fname $ do
        rig <- multiplicity fname
        pat <- bounds (simpleExpr fname indents)
        ty <- (decoratedSymbol fname SymColon *> opExpr pdef fname indents)
                <|> node (TmInfer (boundToFC fname pat))
        pure (rig, pat, ty, Implicit)

  ||| A list of names bound to the same type
  ||| BNF:
  ||| pibindListName := qty name (, name)* ':' typeExpr
  pibindListName : OriginDesc -> IndentInfo ->
                   Rule (RigCount, List1 (WithFC Name), Id FTerm)
  pibindListName fname indents
       = do rig <- multiplicity fname
            ns <- sepBy1 (decoratedSymbol fname SymComma)
                         (fcBounds binderName)
            decoratedSymbol fname SymColon
            ty <- typeExpr pdef fname indents
            atEnd indents
            pure (rig, ns, ty)
    where
      -- _ gets treated specially here, it means "I don't care about the name"
      binderName : Rule Name
      binderName = decoratedSimpleBinderUName fname
               <|> decorate fname Bound (UN <$> symbol SymUnderscore $> Underscore)

  ||| The arrow used after an explicit binder
  ||| BNF:
  ||| bindSymbol := '->' | '=>'
  bindSymbol : OriginDesc -> Rule (PiInfo (Id FTerm))
  bindSymbol fname
      = (decoratedSymbol fname SymArrow $> Explicit)
    <|> (decoratedSymbol fname SymFatArrow $> AutoImplicit)

  ||| An explicit pi-type
  ||| BNF:
  ||| explicitPi := '(' pibindListName ')' bindSymbol typeExpr
  explicitPi : OriginDesc -> IndentInfo -> Rule (Id FTerm)
  explicitPi fname indents
      = do b <- fcBounds (do
               bs <- bounds $ parens fname $ pibindListName fname indents
               exp <- mustWorkBecause bs.bounds "Cannot return a named argument"
                        $ bindSymbol fname
               scope <- mustWork $ typeExpr pdef fname indents
               pure (exp, bs.val, scope))
           let (exp, bound, scope) = b.val
           ns <- multiBinder bound
           bd <- node (BnPi exp ns)
           node (TmNewPi b.fc bd scope)

  ||| An auto-implicit pi-type
  ||| BNF:
  ||| autoImplicitPi := '{' 'auto' pibindListName '}' '->' typeExpr
  autoImplicitPi : OriginDesc -> IndentInfo -> Rule (Id FTerm)
  autoImplicitPi fname indents
      = do b <- fcBounds (do
               bs <- bounds $ curly fname $ do
                      decoratedKeyword fname KwAuto
                      commit
                      binders <- pibindListName fname indents
                      pure binders
               mustWorkBecause bs.bounds "Cannot return an auto implicit argument"
                 $ decoratedSymbol fname SymArrow
               scope <- mustWork $ typeExpr pdef fname indents
               pure (bs.val, scope))
           let (bound, scope) = b.val
           ns <- multiBinder bound
           bd <- node (BnPi AutoImplicit ns)
           node (TmNewPi b.fc bd scope)

  ||| An default implicit pi-type
  ||| BNF:
  ||| defaultImplicitPi := '{' 'default' simpleExpr pibindListName '}' '->' typeExpr
  defaultImplicitPi : OriginDesc -> IndentInfo -> Rule (Id FTerm)
  defaultImplicitPi fname indents
      = do b <- fcBounds (do
               bs <- bounds $ curly fname $ do
                      decoratedKeyword fname KwDefault
                      commit
                      t <- simpleExpr fname indents
                      binders <- pibindListName fname indents
                      pure (t, binders)
               mustWorkBecause bs.bounds "Cannot return a default implicit argument"
                 $ decoratedSymbol fname SymArrow
               scope <- mustWork $ typeExpr pdef fname indents
               pure (bs.val, scope))
           let ((t, bound), scope) = b.val
           ns <- multiBinder bound
           bd <- node (BnPi (DefImplicit t) ns)
           node (TmNewPi b.fc bd scope)

  ||| Forall definition that automatically binds the names
  ||| BNF:
  ||| forall_ := 'forall' name (, name)* '.' typeExpr
  forall_ : OriginDesc -> IndentInfo -> Rule (Id FTerm)
  forall_ fname indents
      = do b <- fcBounds (do
               bs <- bounds $ do
                      decoratedKeyword fname KwForall
                      commit
                      ns <- sepBy1 (decoratedSymbol fname SymComma)
                                   (fcBounds (decoratedSimpleBinderUName fname))
                      pure ns
               b' <- bounds peek
               mustWorkBecause b'.bounds "Expected ',' or '.'"
                 $ decorate fname Keyword (exactSymbol KDot)
               scope <- mustWork $ typeExpr pdef fname indents
               pure (bs.val, scope))
           node (TmForall b.fc (fst b.val) (snd b.val))

  ||| implicit pi-type
  ||| BNF:
  ||| implicitPi := '{' pibindListName '}' '->' typeExpr
  implicitPi : OriginDesc -> IndentInfo -> Rule (Id FTerm)
  implicitPi fname indents
      = do b <- fcBounds (do
               bs <- bounds $ curly fname $ pibindListName fname indents
               mustWorkBecause bs.bounds "Cannot return an implicit argument"
                $ decoratedSymbol fname SymArrow
               scope <- mustWork $ typeExpr pdef fname indents
               pure (bs.val, scope))
           let (bound, scope) = b.val
           ns <- multiBinder bound
           bd <- node (BnPi Implicit ns)
           node (TmNewPi b.fc bd scope)

  lam : OriginDesc -> IndentInfo -> Rule (Id FTerm)
  lam fname indents
      = do decoratedSymbol fname SymBackslash
           commit
           switch <- optional (bounds $ decoratedKeyword fname KwCase)
           case switch of
             Nothing => continueLamImpossible <|> continueLam
             Just r  => continueLamCase r

     where
       -- A lambda matching its argument with `alts`: its variable is
       -- written twice, as the lambda's pattern and as what the case
       -- matches.
       lamCase : (fcCase : FC) -> (fc : FC) -> List (Id FClause) -> EmptyRule (Id FTerm)
       lamCase fcCase fc alts
           = do var <- node (TmRef fcCase (MN (known Klcase) 0))
                inf <- node (TmInfer fcCase)
                body <- node (TmCase (virtualiseFC fc) [] var alts)
                node (TmLam fcCase top Explicit var inf body)

       continueLamImpossible : Rule (Id FTerm)
       continueLamImpossible = do
           lhs <- bounds (opExpr plhs fname indents)
           end <- bounds (decoratedKeyword fname KwImpossible)
           let fc = boundToFC fname (mergeBounds lhs end)
           alt <- node (ClImpossible fc lhs.val)
           lamCase (boundToFC fname lhs) fc [alt]

       bindOne : Id FTerm -> (RigCount, WithBounds (Id FTerm), Id FTerm, PiInfo (Id FTerm)) ->
                 Build (Id FTerm)
       bindOne scope (rig, pat, ty, icit) = make (TmLam (boundToFC fname pat) rig icit pat.val ty scope)

       continueLam : Rule (Id FTerm)
       continueLam = do
           binders <- bindList fname indents
           commitSymbol fname SymFatArrow
           mustContinue indents Nothing
           scope <- typeExpr pdef fname indents
           build (foldlM bindOne scope (reverse binders))

       continueLamCase : WithBounds () -> Rule (Id FTerm)
       continueLamCase endCase = do
           b <- bounds (forget <$> nonEmptyBlock (caseAlt fname))
           lamCase (virtualiseFC $ boundToFC fname endCase) (boundToFC fname b) b.val

  letBlock : OriginDesc -> IndentInfo -> Rule (WithBounds (Either LetBinder LetDecl))
  letBlock fname indents = bounds (letBinder <||> letDecl) where

    letBinder : Rule LetBinder
    letBinder = do s <- bounds (MkPair <$> multiplicity fname <*> expr plhs fname indents)
                   (rig, pat) <- pure s.val
                   ty <- (decoratedSymbol fname SymColon *> typeExpr (pnoeq pdef) fname indents)
                           <|> node (TmImplicit (virtualiseFC $ boundToFC fname s))
                   (decoratedSymbol fname SymEquals <|> decoratedSymbol fname SymAssign)
                   val <- typeExpr pnowith fname indents
                   alts <- block (patAlt fname)
                   pure (MkLetBinder rig pat ty val alts)

    letDecl : Rule LetDecl
    letDecl = forget <$> nonEmptyBlock (try . topDecl fname)

  let_ : OriginDesc -> IndentInfo -> Rule (Id FTerm)
  let_ fname indents
      = do decoratedKeyword fname KwLet
           commit
           res <- nonEmptyBlock (letBlock fname)
           commitKeyword fname indents KwIn
           scope <- typeExpr pdef fname indents
           build (mkLets fname res scope)

  case_ : OriginDesc -> IndentInfo -> Rule (Id FTerm)
  case_ fname indents
      = do opts <- many (fnDirectOpt fname)
           b <- bounds (do decoratedKeyword fname KwCase
                           scr <- expr pdef fname indents
                           mustWork (commitKeyword fname indents KwOf)
                           alts <- block (caseAlt fname)
                           pure (scr, alts))
           (scr, alts) <- pure b.val
           node (TmCase (virtualiseFC $ boundToFC fname b) opts scr alts)


  caseAlt : OriginDesc -> IndentInfo -> Rule (Id FClause)
  caseAlt fname indents
      = do lhs <- bounds (opExpr plhs fname indents)
           caseRHS fname lhs indents lhs.val

  caseRHS : OriginDesc -> WithBounds t -> IndentInfo -> Id FTerm -> Rule (Id FClause)
  caseRHS fname start indents lhs
      = do rhs <- bounds $ do
                    decoratedSymbol fname SymFatArrow
                    mustContinue indents Nothing
                    typeExpr pdef fname indents
           atEnd indents
           let fc = boundToFC fname (mergeBounds start rhs)
           node (ClPattern fc lhs rhs.val [])
    <|> do end <- bounds (decoratedKeyword fname KwImpossible)
           atEnd indents
           node (ClImpossible (boundToFC fname (mergeBounds start end)) lhs)
    <|> fatalError ("Expected '=>' or 'impossible'")

  if_ : OriginDesc -> IndentInfo -> Rule (Id FTerm)
  if_ fname indents
      = do b <- bounds (do decoratedKeyword fname KwIf
                           commit
                           x <- expr pdef fname indents
                           commitKeyword fname indents KwThen
                           t <- typeExpr pdef fname indents
                           commitKeyword fname indents KwElse
                           e <- typeExpr pdef fname indents
                           pure (x, t, e))
           mustWork $ atEnd indents
           (x, t, e) <- pure b.val
           node (TmIfThenElse (boundToFC fname b) x t e)

  record_ : OriginDesc -> IndentInfo -> Rule (Id FTerm)
  record_ fname indents
      = do
           b <- (
               withWarning oldSyntaxWarning (
                 bounds (do
                   decoratedKeyword fname KwRecord
                   commit
                   body True
                 ))
             <|>
               bounds (body False))
           node (TmUpdate (boundToFC fname b) (forget b.val))
    where
      oldSyntaxWarning : String
      oldSyntaxWarning = unlines
        [ "DEPRECATED: old record update syntax."
        , #"  Use "{ f := v } p" instead of "record { f = v } p""#
        , #"  and "{ f $= v } p" instead of "record { f $= v } p""#
        ]

      body : Bool -> Rule (List1 (Id FUpdate))
      body kw = curly fname $ do
        commit
        sepBy1 (decoratedSymbol fname SymComma) (field kw fname indents)

  field : Bool -> OriginDesc -> IndentInfo -> Rule (Id FUpdate)
  field kw fname indents
      = do path <- [| fieldPart (decorate fname Function name) :: many (fieldPart recFieldCompat) |]
           upd <- (ifThenElse kw (decoratedSymbol fname SymEquals) (decoratedSymbol fname SymAssign) $> UpSet)
                      <|>
                  (decoratedSymbol fname SymUpdate $> UpApply)
           val <- typeExpr plhs fname indents
           node (upd path val)
    where
      fieldName : Name -> Maybe Ident
      fieldName (UN (Basic s)) = Just s
      fieldName (UN (Field s)) = Just s
      fieldName _ = Nothing

      -- A path names each field by its identifier, so a name that is no
      -- field's (a qualified one) is refused here, where it is written.
      fieldPart : Rule Name -> Rule Ident
      fieldPart rule
          = do n <- rule
               the (EmptyRule Ident) $ case fieldName n of
                    Just i => pure i
                    Nothing => fail "Expected a record field name"

      -- this allows the dotted syntax .field
      -- but also the arrowed syntax ->field for compatibility with Idris 1
      recFieldCompat : Rule Name
      recFieldCompat = decorate fname Function postfixProj
                  <|> (decoratedSymbol fname SymArrow
                       *> decorate fname Function name)

  rewrite_ : OriginDesc -> IndentInfo -> Rule (Id FTerm)
  rewrite_ fname indents
      = do b <- bounds (do decoratedKeyword fname KwRewrite
                           rule <- expr pdef fname indents
                           commitKeyword fname indents KwIn
                           tm <- typeExpr pdef fname indents
                           pure (rule, tm))
           (rule, tm) <- pure b.val
           node (TmRewrite (boundToFC fname b) rule tm)

  doBlock : OriginDesc -> IndentInfo -> Rule (Id FTerm)
  doBlock fname indents
      = do b <- bounds $ decoratedKeyword fname KwDo *> block (doAct fname)
           commit
           node (TmDoBlock (virtualiseFC $ boundToFC fname b) Nothing (concat b.val))
    <|> do nsdo <- bounds namespacedIdent
           -- TODO: need to attach metadata correctly here
           the (EmptyRule (Id FTerm)) $ case nsdo.val of
                (ns, n) =>
                   if n == known Kdo
                      then do commit
                              actions <- Core.bounds (block (doAct fname))
                              let fc = virtualiseFC $
                                       boundToFC fname (mergeBounds nsdo actions)
                              node (TmDoBlock fc ns (concat actions.val))
                      else fail "Not a namespaced 'do'"

  validPatternVar : Name -> EmptyRule ()
  validPatternVar (UN Underscore) = pure ()
  validPatternVar (UN (Basic n))
      = unless (lowerFirst n.text) $
          fail "Not a pattern variable"
  validPatternVar _ = fail "Not a pattern variable"

  doAct : OriginDesc -> IndentInfo -> Rule (List (Id FDo))
  doAct fname indents
      = do b <- bounds (do rig <- multiplicity fname
                           n <- bounds (name <|> UN Underscore <$ symbol SymUnderscore)
                           -- If the name doesn't begin with a lower case letter, we should
                           -- treat this as a pattern, so fail
                           validPatternVar n.val
                           ty <- optional (decoratedSymbol fname SymColon *> typeExpr (pnoeq pdef) fname indents)
                           decoratedSymbol fname SymLeftArrow
                           val <- expr pdef fname indents
                           pure (n, rig, ty, val))
           atEnd indents
           let (n, rig, ty, val) = b.val
           st <- node (StBind (boundToFC fname b) (boundToFC fname n) n.val rig ty val)
           pure [st]
    <|> do decoratedKeyword fname KwLet
           commit
           res <- nonEmptyBlock (letBlock fname)
           do b <- bounds (decoratedKeyword fname KwIn)
              fatalLoc {c = True} b.bounds "Let-in not supported in do block. Did you mean (let ... in ...)?"
             <|>
           do atEnd indents
              build (mkDoLets fname res)
    <|> do b <- bounds (decoratedKeyword fname KwRewrite *> expr pdef fname indents)
           atEnd indents
           st <- node (StRewrite (boundToFC fname b) b.val)
           pure [st]
    <|> do e <- bounds (expr plhs fname indents)
           (do atEnd indents
               st <- node (StExp (virtualiseFC $ boundToFC fname e) e.val)
               pure [st])
             <|> (do ty <- optional (decoratedSymbol fname SymColon *> typeExpr (pnoeq pdef) fname indents)
                     b <- bounds $ decoratedSymbol fname SymLeftArrow *> [| (expr pnowith fname indents, block (patAlt fname)) |]
                     atEnd indents
                     let (v, alts) = b.val
                     let fc = virtualiseFC $ boundToFC fname (mergeBounds e b)
                     st <- node (StBindPat fc e.val ty v alts)
                     pure [st])

  patAlt : OriginDesc -> IndentInfo -> Rule (Id FClause)
  patAlt fname indents
      = do decoratedSymbol fname SymBar
           caseAlt fname indents

  lazy : OriginDesc -> IndentInfo -> Rule (Id FTerm)
  lazy fname indents
      = do tm <- bounds (decorate fname Typ (exactIdent KLazy)
                         *> simpleExpr fname indents
                         <* mustFailBecause "Lazy only takes one argument" (continue indents >> simpleExpr fname indents))
           node (TmDelayed (boundToFC fname tm) LLazy tm.val)
    <|> do tm <- bounds (decorate fname Typ (exactIdent KInf)
                         *> simpleExpr fname indents
                         <* mustFailBecause "Inf only takes one argument" (continue indents >> simpleExpr fname indents))
           node (TmDelayed (boundToFC fname tm) LInf tm.val)
    <|> do tm <- bounds (decorate fname Data (exactIdent KDelay)
                         *> simpleExpr fname indents
                         <* mustFailBecause "Delay only takes one argument" (continue indents >> simpleExpr fname indents))
           node (TmDelay (boundToFC fname tm) tm.val)
    <|> do tm <- bounds (decorate fname Data (exactIdent KForce)
                         *> simpleExpr fname indents
                         <* mustFailBecause "Force only takes one argument" (continue indents >> simpleExpr fname indents))
           node (TmForce (boundToFC fname tm) tm.val)

  binder : OriginDesc -> IndentInfo -> Rule (Id FTerm)
  binder fname indents
      = autoImplicitPi fname indents
    <|> defaultImplicitPi fname indents
    <|> forall_ fname indents
    <|> implicitPi fname indents
    <|> autobindOp pdef fname indents
    <|> explicitPi fname indents
    <|> lam fname indents

  typeExpr : ParseOpts -> OriginDesc -> IndentInfo -> Rule (Id FTerm)
  typeExpr q fname indents
      = binder fname indents
    <|> do arg_mscope <- bounds $ do
             arg <- expr q fname indents
             mscope <- optional $ do
                 continue indents
                 bd <- bindSymbol fname
                 scope <- mustWork $ typeExpr q fname indents
                 pure (bd, scope)
             pure (arg, mscope)
           mkPi (boundToFC fname arg_mscope) arg_mscope.val

    where
      mkPi : FC -> (Id FTerm, Maybe (PiInfo (Id FTerm), Id FTerm)) -> EmptyRule (Id FTerm)
      mkPi _ (arg, Nothing) = pure arg
      mkPi fc (arg, Just (exp, a))
        = node (TmPi fc top exp Nothing arg a)

  export
  expr : ParseOpts -> OriginDesc -> IndentInfo -> Rule (Id FTerm)
  expr q fname indents
       = let_ fname indents
     <|> rewrite_ fname indents
     <|> do b <- bounds $
                   do decoratedPragma fname KwRunElab
                      expr pdef fname indents
            node (TmRunElab (boundToFC fname b) b.val)
     <|> opExpr q fname indents

  interpBlock : ParseOpts -> OriginDesc -> IndentInfo -> Rule (Id FTerm)
  interpBlock q fname idents = interpBegin *> (mustWork $ expr q fname idents <* interpEnd)

  export
  singlelineStr : ParseOpts -> OriginDesc -> IndentInfo -> Rule (Id FTerm)
  singlelineStr q fname idents
      = decorate fname Data $
        do b <- bounds $ do begin <- bounds strBegin
                            commit
                            xs <- many $ bounds $ (interpBlock q fname idents) <||> strLitLines
                            pstrs <- case traverse toPStr xs of
                                          Left err => fatalLoc begin.bounds err
                                          Right pieces => build (traverse (make {x = FStr}) pieces)
                            strEnd
                            pure (begin.val, pstrs)
           let (hashtag, str) = b.val
           node (TmString (boundToFC fname b) hashtag str)
    where
      toPStr : (WithBounds $ Either (Id FTerm) (List1 String)) -> Either String (NodeOf Id)
      toPStr x = case x.val of
                      Right (str:::[]) => Right $ PcLiteral (boundToFC fname x) str
                      Right (_:::strs) => Left "Multi-line string is expected to begin with \"\"\""
                      Left tm => Right $ PcInterp (boundToFC fname x) tm

  export
  multilineStr : ParseOpts -> OriginDesc -> IndentInfo -> Rule (Id FTerm)
  multilineStr q fname idents
      = decorate fname Data $
        do b <- bounds $ do hashtag <- multilineBegin
                            commit
                            xs <- many $ bounds $ (interpBlock q fname idents) <||> strLitLines
                            endloc <- location
                            strEnd
                            pure (hashtag, endloc, toLines xs [<] [<])
           let (hashtag, (_, col), xs) = b.val
           strLines <- build (traverse (traverse (make {x = FStr})) xs)
           node (TmMultiline (boundToFC fname b) hashtag (fromInteger $ cast col) strLines)
    where
      toLines : List (WithBounds $ Either (Id FTerm) (List1 String)) ->
                SnocList (NodeOf Id) -> SnocList (List (NodeOf Id)) -> List (List (NodeOf Id))
      toLines [] line acc = acc <>> [line <>> []]
      toLines (x::xs) line acc = case x.val of
        Left tm =>
          toLines xs (line :< PcInterp (boundToFC fname x) tm) acc
        Right (str:::[]) =>
          toLines xs (line :< PcLiteral (boundToFC fname x) str) acc
        Right (str:::strs@(_::_)) =>
          let fc = boundToFC fname x in
          toLines xs [< PcLiteral fc (last strs)]
            $ acc :< (line <>> [PcLiteral fc str])
            <>< map (\str => [PcLiteral fc str]) (init strs)

  fnDirectOpt : OriginDesc -> Rule (Id FOpt)
  fnDirectOpt fname
      = do decoratedPragma fname KwHint
           node (OpFn (Hint True))
    <|> do decoratedPragma fname KwGlobalHint
           node (OpFn (GlobalHint False))
    <|> do decoratedPragma fname KwDefaultHint
           node (OpFn (GlobalHint True))
    <|> do decoratedPragma fname KwInline
           commit
           node (OpFn Inline)
    <|> do decoratedPragma fname KwUnsafe
           commit
           node (OpFn Unsafe)
    <|> do decoratedPragma fname KwNoInline
           commit
           node (OpFn NoInline)
    <|> do decoratedPragma fname KwDeprecate
           commit
           node (OpFn Deprecate)
    <|> do decoratedPragma fname KwTCInline
           commit
           node (OpFn TCInline)
    <|> do decoratedPragma fname KwExtern
           node (OpFn ExternFn)
    <|> do decoratedPragma fname KwMacro
           node (OpFn Macro)
    <|> do decoratedPragma fname KwSpec
           ns <- sepBy (decoratedSymbol fname SymComma) name
           node (OpFn (SpecArgs ns))
    <|> do decoratedPragma fname KwForeign
           cs <- block (expr pdef fname)
           node (OpForeign cs)
    <|> do (decoratedPragma fname KwExport
            <|> withWarning noMangleWarning
                (decoratedPragma fname KwNoMangle))
           cs <- block (expr pdef fname)
           node (OpForeignExport cs)
    where
      noMangleWarning : String
      noMangleWarning = """
      DEPRECATED: "%nomangle".
        Use "%export" instead
      """


visOption : OriginDesc ->  Rule Visibility
visOption fname
    = (decoratedKeyword fname KwPublic *> decoratedKeyword fname KwExport $> Public)
    -- If "public export" failed then we try to parse just "public" and emit an error message saying
    -- the user should use "public export"
  <|> (bounds (decoratedKeyword fname KwPublic) >>= \x : WithBounds ()
    => the (Rule Visibility) (fatalLoc x.bounds
           #""public" keyword by itself is not an export modifier, did you mean "public export"?"#))
  <|> (decoratedKeyword fname KwExport $> Export)
  <|> (decoratedKeyword fname KwPrivate $> Private)


visibility : OriginDesc -> EmptyRule (WithDefault Visibility Private)
visibility fname
    = (specified <$> visOption fname)
  <|> pure defaulted

exportVisibility : OriginDesc -> EmptyRule (WithDefault Visibility Export)
exportVisibility fname
    = (specified <$> visOption fname)
  <|> pure defaulted

||| A binder with only one name and one type
||| BNF:
||| plainBinder := name ':' typeExpr
plainBinder : (fname : OriginDesc) => (indents : IndentInfo) => Rule (Id FPlain)
plainBinder = do name <- fcBounds (decoratedSimpleBinderUName fname)
                 decoratedSymbol fname SymColon
                 ty <- typeExpr pdef fname indents
                 node (BnPlain name ty)

||| A binder with multiple names and one type
||| BNF:
||| basicMultiBinder := name (, name)* ':' typeExpr
basicMultiBinder : (fname : OriginDesc) => (indents : IndentInfo) => Rule (Id FNames)
basicMultiBinder
  = do rig <- multiplicity fname
       names <- sepBy1 (decoratedSymbol fname SymComma)
                     $ fcBounds (decoratedSimpleBinderUName fname)
       decoratedSymbol fname SymColon
       ty <- typeExpr pdef fname indents
       node (BnNames rig names ty)

tyDecls : Rule Name -> String -> OriginDesc -> IndentInfo -> Rule (Id FTyDecl)
tyDecls declName predoc fname indents
    = do bs <- bounds $ do
                  docns <- sepBy1 (decoratedSymbol fname SymComma)
                                  [| (optDocumentation fname, fcBounds declName) |]
                  b <- bounds $ decoratedSymbol fname SymColon
                  mustWorkBecause b.bounds "Expected a type declaration" $ do
                    ty <- the (Rule (Id FTerm)) (typeExpr pdef fname indents)
                    pure (docns, ty)
         atEnd indents
         let (docns, ty) = bs.val
         node (TyClaim (boundToFC fname bs) docns predoc ty)

withFlags : OriginDesc -> EmptyRule (List WithFlag)
withFlags fname
    = (do decoratedPragma fname KwSyntactic
          (Syntactic ::) <$> withFlags fname)
  <|> pure []


withProblem : OriginDesc -> Int -> IndentInfo -> Rule (Id FWith)
withProblem fname col indents
  = do rig <- multiplicity fname
       start <- mustWork $ bounds (decoratedSymbol fname SymParen)
       wval <- bracketedExpr fname start indents
       prf <- optional $ do
                decoratedKeyword fname KwProof
                pure (!(multiplicity fname), !(decoratedSimpleBinderUName fname))
       node (WpValue rig wval prf)

mutual
  parseRHS : (withArgs : Nat) ->
             OriginDesc -> WithBounds t -> Int ->
             IndentInfo -> (lhs : (Id FTerm, List (FC, Id FTerm))) -> Rule (Id FClause)
  parseRHS withArgs fname start col indents lhs
       = do b <- bounds $ do
                   decoratedSymbol fname SymEquals
                   mustWork $ do
                     continue indents
                     rhs <- typeExpr pdef fname indents
                     ws <- option [] $ whereBlock fname col
                     pure (rhs, ws)
            b' <- bounds peek
            mustWorkBecause b'.bounds "Not the end of a block entry, check indentation" $ atEnd indents
            (rhs, ws) <- pure b.val
            let fc = boundToFC fname (mergeBounds start b)
            l <- withApplied lhs
            node (ClPattern fc l rhs ws)
     <|> do b <- bounds $ do
                   decoratedKeyword fname KwWith
                   commit
                   flags <- withFlags fname
                   wps <- sepBy1 (decoratedSymbol fname SymBar) (withProblem fname col indents)
                   ws <- mustWork $ nonEmptyBlockAfter col
                                  $ clause (S (length wps.tail) + withArgs) (Just lhs) fname
                   pure (flags, wps, forget ws)
            (flags, wps, ws) <- pure b.val
            let fc = boundToFC fname (mergeBounds start b)
            l <- withApplied lhs
            node (ClWith fc l wps flags ws)
     <|> do end <- bounds (decoratedKeyword fname KwImpossible)
            atEnd indents
            l <- withApplied lhs
            node (ClImpossible (boundToFC fname (mergeBounds start end)) l)

  clause : (withArgs : Nat) ->
           IMaybe (isSucc withArgs) (Id FTerm, List (FC, Id FTerm)) ->
           OriginDesc -> IndentInfo -> Rule (Id FClause)
  clause withArgs mlhs fname indents
      = do b <- bounds (do col   <- column
                           lhsws <- clauseLHS fname indents mlhs
                           extra <- many parseWithArg
                           pure (col, mapSnd (++ extra) lhsws))
           let col = Builtin.fst b.val
           let lhs = Builtin.snd b.val
           let extra = Builtin.snd lhs
           -- Can't have the dependent 'if' here since we won't be able
           -- to infer the termination status of the rule
           ifThenElse (withArgs /= length extra)
              (fatalError $ "Wrong number of 'with' arguments:"
                         ++ " expected " ++ show withArgs
                         ++ " but got " ++ show (length extra))
              (parseRHS withArgs fname b col indents lhs)
    where

      clauseLHS : OriginDesc -> IndentInfo ->
                  IMaybe b (Id FTerm, List (FC, Id FTerm)) ->
                  Rule (Id FTerm, List (FC, Id FTerm))
      -- we aren't in a `with` so there is nothing to skip
      clauseLHS fname indent Nothing
        = (,[]) <$> opExpr plhs fname indents
      -- in a with clause, give a different meaning to a `_` lhs
      clauseLHS fname indent (Just lhs)
        = do e <- opExpr plhs fname indents
             Just fc <- build (implicitAt e)
               | Nothing => pure (e, [])
             relocated (virtualiseFC fc) lhs

      parseWithArg : Rule (FC, Id FTerm)
      parseWithArg
          = do decoratedSymbol fname SymBar
               tm <- bounds (expr plhs fname indents)
               pure (boundToFC fname tm, tm.val)

-- A type constructor's type: a `Type` for each parameter, and `Type`. The
-- one `Type` is every one of them.
tyConType : OriginDesc -> FC -> List (WithBounds Name) -> EmptyRule (Id FTerm)
tyConType fname fc params
    = do ty <- node (TmType (virtualiseFC fc))
         build (foldlM (\rest, x => make (TmPi (boundToFC fname x) top Explicit Nothing ty rest))
                       ty (reverse params))

-- A constructor's argument in a simple data declaration: explicit or auto
-- implicit, as only these may be.
conArg : WithFC ArgType -> Maybe (FC, PiInfo (Id FTerm), Id FTerm)
conArg con@(MkWithData _ (UnnamedExpArg x)) = Just (con.fc, Explicit, x)
conArg con@(MkWithData _ (UnnamedAutoArg x)) = Just (con.fc, AutoImplicit, x)
conArg _ = Nothing -- with and named applications not allowed in simple ADTs

-- A constructor's type in a simple data declaration: its arguments, and the
-- type it returns.
dataConType : Id FTerm -> List (FC, PiInfo (Id FTerm), Id FTerm) -> EmptyRule (Id FTerm)
dataConType ret args
    = build (foldlM (\rest, (fc, info, x) => make (TmPi fc top info Nothing x rest))
                    ret (reverse args))

simpleCon : OriginDesc -> Id FTerm -> IndentInfo -> Rule (Id FTyDecl)
simpleCon fname ret indents
    = do b <- bounds (do cdoc   <- optDocumentation fname
                         cname  <- fcBounds $ decoratedDataConstructorName fname
                         params <- the (EmptyRule $ List $ WithFC $ List ArgType)
                                     $ many (fcBounds $ argExpr plhs fname indents)
                         let Just args = traverse conArg (concat (map distribData params))
                               | Nothing => fatalError "Named arguments not allowed in ADT constructors"
                         conType <- dataConType ret args
                         pure (cdoc, cname, conType))
         atEnd indents
         let (cdoc, cname, conType) = b.val
         node (TyClaim (boundToFC fname b) (singleton ("", cname)) cdoc conType)

simpleData : OriginDesc -> WithBounds t ->
             WithBounds Name -> IndentInfo -> Rule (Id FData)
simpleData fname start tyName indents
    = do b <- bounds (do params <- many (bounds $ decorate fname Bound name)
                         tyend <- bounds (decoratedSymbol fname SymEquals)
                         mustWork $ do
                           let tyfc = boundToFC fname (mergeBounds start tyend)
                           tyCon <- node (TmRef (boundToFC fname tyName) tyName.val)
                           args <- build (traverse (\ t => make (TmRef (boundToFC fname t) t.val)) params)
                           -- every constructor's return type, one node
                           conRetTy <- build (foldlM (\f, a => make (TmApp tyfc f a)) tyCon args)
                           cons <- sepBy1 (decoratedSymbol fname SymBar) (simpleCon fname conRetTy indents)
                           pure (params, tyfc, forget cons))
         (params, tyfc, cons) <- pure b.val
         tyConTy <- tyConType fname tyfc params
         node (DtBody (boundToFC fname (mergeBounds start b)) tyName.val (Just tyConTy) [] cons)

dataOpt : OriginDesc -> Rule DataOpt
dataOpt fname
    = (decorate fname Keyword (exactIdent KnoHints) $> NoHints)
  <|> (decorate fname Keyword (exactIdent KuniqueSearch) $> UniqueSearch)
  <|> (do b   <- bounds $ decorate fname Keyword (exactIdent Ksearch)
          det <- mustWorkBecause b.bounds "Expected list of determining parameters" $
                   some (decorate fname Bound name)
          pure $ SearchBy det)
  <|> (decorate fname Keyword (exactIdent Kexternal) $> External)
  <|> (decorate fname Keyword (exactIdent KnoNewtype) $> NoNewtype)

dataOpts : OriginDesc -> EmptyRule (List DataOpt)
dataOpts fname = option [] $ do
  decoratedSymbol fname SymBracket
  opts <- sepBy1 (decoratedSymbol fname SymComma) (dataOpt fname)
  decoratedSymbol fname SymBracketClose
  pure (forget opts)

dataBody : OriginDesc -> Int -> WithBounds t -> Name -> IndentInfo -> Maybe (Id FTerm) ->
          EmptyRule (Id FData)
dataBody fname mincol start n indents ty
    = do ty <- maybe (fail "Telescope is not optional in forward declaration") pure ty
         atEndIndent indents
         node (DtLater (boundToFC fname start) n ty)
  <|> do b <- bounds (do (mustWork $ decoratedKeyword fname KwWhere)
                         opts <- dataOpts fname
                         cs <- blockAfter mincol (tyDecls (mustWork $ decoratedDataConstructorName fname) "" fname)
                         pure (opts, cs))
         (opts, cs) <- pure b.val
         node (DtBody (boundToFC fname (mergeBounds start b)) n ty opts cs)

gadtData : OriginDesc -> Int -> WithBounds t ->
           WithBounds Name -> IndentInfo -> EmptyRule (Id FData)
gadtData fname mincol start tyName indents
    = do ty <- optional $
                 do decoratedSymbol fname SymColon
                    commit
                    typeExpr pdef fname indents
         dataBody fname mincol start tyName.val indents ty

dataDeclBody : OriginDesc -> IndentInfo -> Rule (Id FData)
dataDeclBody fname indents
    = do b <- bounds (do col <- column
                         decoratedKeyword fname KwData
                         n <- mustWork (bounds $ decoratedDataTypeName fname)
                         pure (col, n))
         (col, n) <- pure b.val
         simpleData fname b n indents <|> gadtData fname col b n indents

-- a data declaration can have a visibility and an optional totality (#1404)
dataVisOpt : OriginDesc -> EmptyRule (WithDefault Visibility Private, Maybe TotalReq)
dataVisOpt fname
    = do { vis <- visOption   fname ; mbtot <- optional (totalityOpt fname) ; pure (specified vis, mbtot) }
  <|> do { tot <- totalityOpt fname ; vis <- visibility fname ; pure (vis, Just tot) }
  <|> pure (defaulted, Nothing)

dataDecl : (fname : OriginDesc) => (indents : IndentInfo) => Rule (DeclOf Id)
dataDecl
    = do doc         <- optDocumentation fname
         (vis,mbTot) <- dataVisOpt fname
         dat         <- dataDeclBody fname indents
         pure (DcData doc vis mbTot dat)

stripBraces : String -> String
stripBraces str = pack (drop '{' (reverse (drop '}' (reverse (unpack str)))))
  where
    drop : Char -> List Char -> List Char
    drop c [] = []
    drop c (c' :: xs) = if c == c' then drop c xs else c' :: xs

onoff : Rule Bool
onoff
   = (exactIdent Kon $> True)
 <|> (exactIdent Koff $> False)
 <|> fail "expected 'on' or 'off'"

extension : Rule LangExt
extension
    = (exactIdent KElabReflection $> ElabReflection)
  <|> fail "expected 'ElabReflection'"

logLevel : OriginDesc -> Rule (Maybe LogLevel)
logLevel fname
  = (Nothing <$ decorate fname Keyword (exactIdent Koff))
    <|> do topic <- optional (split ('.' ==) <$> simpleStr)
           lvl <- intLit
           pure (Just (mkLogLevel' topic (fromInteger lvl)))
    <|> fail "expected a log level"

directive : (fname : OriginDesc) => (indents : IndentInfo) => Rule (Directive' (Id FTerm))
directive
    = do decoratedPragma fname KwHide
         n <- (fixityNS <|> (HideName <$> name))
         atEnd indents
         pure (Hide n)
  <|> do decoratedPragma fname KwUnhide
         n <- name
         atEnd indents
         pure (Unhide n)
--   <|> do pragma "hide_export"
--          n <- name
--          atEnd indents
--          pure (Hide True n)
  <|> do decoratedPragma fname KwLogging
         lvl <- logLevel fname
         atEnd indents
         pure (Logging lvl)
  <|> do decoratedPragma fname KwAutoLazy
         b <- onoff
         atEnd indents
         pure (LazyOn b)
  <|> do decoratedPragma fname KwUnboundImplicits
         b <- onoff
         atEnd indents
         pure (UnboundImplicits b)
  <|> do decoratedPragma fname KwPrefixRecordProjections
         b <- onoff
         atEnd indents
         pure (PrefixRecordProjections b)
  <|> do decoratedPragma fname KwNfMetavarThreshold
         dpt <- decorate fname Keyword $ intLit
         atEnd indents
         pure (NFMetavarThreshold (fromInteger dpt))
  <|> do decoratedPragma fname KwPair
         ty <- name
         f <- name
         s <- name
         atEnd indents
         pure (PairNames ty f s)
  <|> do decoratedPragma fname KwRewrite
         eq <- name
         rw <- name
         atEnd indents
         pure (RewriteName eq rw)
  <|> do decoratedPragma fname KwIntegerLit
         n <- name
         atEnd indents
         pure (PrimInteger n)
  <|> do decoratedPragma fname KwStringLit
         n <- name
         atEnd indents
         pure (PrimString n)
  <|> do decoratedPragma fname KwCharLit
         n <- name
         atEnd indents
         pure (PrimChar n)
  <|> do decoratedPragma fname KwDoubleLit
         n <- name
         atEnd indents
         pure (PrimDouble n)
  <|> do decoratedPragma fname KwTTImpLit
         n <- name
         atEnd indents
         pure (PrimTTImp n)
  <|> do decoratedPragma fname KwNameLit
         n <- name
         atEnd indents
         pure (PrimName n)
  <|> do decoratedPragma fname KwDeclsLit
         n <- name
         atEnd indents
         pure (PrimDecls n)
  <|> do decoratedPragma fname KwName
         n <- name
         ns <- sepBy1 (decoratedSymbol fname SymComma)
                      (decoratedSimpleBinderUName fname)
         atEnd indents
         pure (Names n (forget (map nameRoot ns)))
  <|> do decoratedPragma fname KwStart
         e <- expr pdef fname indents
         atEnd indents
         pure (StartExpr e)
  <|> do decoratedPragma fname KwAllowOverloads
         n <- name
         atEnd indents
         pure (Overloadable n)
  <|> do decoratedPragma fname KwLanguage
         e <- mustWork extension
         atEnd indents
         pure (Extension e)
  <|> do decoratedPragma fname KwDefault
         tot <- totalityOpt fname
         atEnd indents
         pure (DefaultTotality tot)

fix : Rule Fixity
fix
    = (keyword KwInfixl $> InfixL)
  <|> (keyword KwInfixr $> InfixR)
  <|> (keyword KwInfix  $> Infix)
  <|> (keyword KwPrefix $> Prefix)

namespaceHead : OriginDesc -> Rule Namespace
namespaceHead fname
  = do decoratedKeyword fname KwNamespace
       decorate fname Namespace $ mustWork namespaceId

parameters {auto fname : OriginDesc} {auto indents : IndentInfo}
  namespaceDecl : Rule (DeclOf Id)
  namespaceDecl
      = do doc <- optDocumentation fname -- documentation is not recoded???
           col <- column
           ns  <- namespaceHead fname
           ds  <- blockAfter col (topDecl fname)
           pure (DcNamespace ns ds)

  transformDecl : Rule (DeclOf Id)
  transformDecl
      = do decoratedPragma fname KwTransform
           n <- simpleStr
           lhs <- expr plhs fname indents
           decoratedSymbol fname SymEquals
           rhs <- expr pnowith fname indents
           pure (DcTransform n lhs rhs)

  runElabDecl : Rule (DeclOf Id)
  runElabDecl
      = do
           decoratedPragma fname KwRunElab
           tm <- expr pnowith fname indents
           pure (DcRunElab tm)

  ||| failDecls := 'failing' simpleStr? nonEmptyBlock
  failDecls : Rule (DeclOf Id)
  failDecls
      = do
           col <- column
           decoratedKeyword fname KwFailing
           commit
           msg <- optional (decorate fname Data (simpleMultiStr <|> simpleStr ))
           ds <- nonEmptyBlockAfter col (topDecl fname)
           pure $ DcFail msg (forget ds)

  ||| mutualDecls := 'mutual' nonEmptyBlock
  mutualDecls : Rule (DeclOf Id)
  mutualDecls
      = do
           col <- column
           decoratedKeyword fname KwMutual
           commit
           ds <- nonEmptyBlockAfter col (topDecl fname)
           pure (DcMutual (forget ds))

  usingDecls : Rule (DeclOf Id)
  usingDecls
      = do col <- column
           decoratedKeyword fname KwUsing
           commit
           decoratedSymbol fname SymParen
           us <- sepBy (decoratedSymbol fname SymComma)
                       (do n <- optional $ userName <* decoratedSymbol fname SymColon
                           ty <- typeExpr pdef fname indents
                           pure (n, ty))
           decoratedSymbol fname SymParenClose
           ds <- nonEmptyBlockAfter col (topDecl fname)
           pure (DcUsing us (forget ds))

  ||| builtinDecl := 'builtin' builtinType name
  builtinDecl : Rule (DeclOf Id)
  builtinDecl
      = do decoratedPragma fname KwBuiltin
           commit
           t <- builtinType
           n <- name
           pure $ DcBuiltin t n

visOpt : OriginDesc -> Rule (Either Visibility (Id FOpt))
visOpt fname
    = do vis <- visOption fname
         pure (Left vis)
  <|> do tot <- fnOpt fname
         pure (Right tot)
  <|> do opt <- fnDirectOpt fname
         pure (Right opt)

getVisibility : Maybe Visibility -> List (Either Visibility (Id FOpt)) ->
                EmptyRule Visibility
getVisibility Nothing [] = pure Private
getVisibility (Just vis) [] = pure vis
getVisibility Nothing (Left x :: xs) = getVisibility (Just x) xs
getVisibility (Just vis) (Left x :: xs)
   = fatalError "Multiple visibility modifiers"
getVisibility v (_ :: xs) = getVisibility v xs

recordConstructor : OriginDesc -> Rule (WithDoc $ AddFC Name)
recordConstructor fname
  = do doc <- optDocumentation fname
       decorate fname Keyword $ exactIdent Kconstructor
       n <- fcBounds $ mustWork $ decoratedDataConstructorName fname
       pure (doc :+ n)

autoImplicitField : OriginDesc -> IndentInfo -> Rule (PiInfo t)
autoImplicitField fname _ = AutoImplicit <$ decoratedKeyword fname KwAuto

defImplicitField : OriginDesc -> IndentInfo -> Rule (PiInfo (Id FTerm))
defImplicitField fname indents = do
  decoratedKeyword fname KwDefault
  commit
  t <- simpleExpr fname indents
  pure (DefImplicit t)

constraints : OriginDesc -> IndentInfo -> EmptyRule (List (Maybe Name, Id FTerm))
constraints fname indents
    = do tm <- appExpr pdef fname indents
         decoratedSymbol fname SymFatArrow
         more <- constraints fname indents
         pure ((Nothing, tm) :: more)
  <|> do decoratedSymbol fname SymParen
         n <- decorate fname Bound name
         decoratedSymbol fname SymColon
         tm <- typeExpr pdef fname indents
         decoratedSymbol fname SymParenClose
         decoratedSymbol fname SymFatArrow
         more <- constraints fname indents
         pure ((Just n, tm) :: more)
  <|> pure []

-- An implementation's implicit parameters, one for each name bound, each
-- where its name is.
implBinds : OriginDesc -> IndentInfo -> (namedImpl : Bool) ->
            EmptyRule (List (Id FImplicit))
implBinds fname indents namedImpl = concat <$> go where

  isDefaultImplicit : PiInfo a -> Bool
  isDefaultImplicit (DefImplicit _) = True
  isDefaultImplicit _               = False

  go : EmptyRule (List (List (Id FImplicit)))
  go = do decoratedSymbol fname SymBrace
          piInfo <- bounds $ option Implicit $ defImplicitField fname indents
          when (not namedImpl && isDefaultImplicit piInfo.val) $
            fatalLoc piInfo.bounds "Default implicits are allowed only for named implementations"
          (rig, names, type) <- pibindListName fname indents
          ns <- build (traverse (\nm => make (BnImplicit (virtualiseFC nm.fc) rig nm piInfo.val type))
                                (forget names))
          commitSymbol fname SymBraceClose
          commitSymbol fname SymArrow
          more <- go
          pure (ns :: more)
    <|> pure []

fieldDecl : (fname : OriginDesc) => IndentInfo -> Rule (Id FField)
fieldDecl indents
      = do doc <- optDocumentation fname
           decoratedSymbol fname SymBrace
           commit
           impl <- option Implicit (autoImplicitField fname indents <|> defImplicitField fname indents)
           fs <- fieldBody doc impl
           decoratedSymbol fname SymBraceClose
           atEnd indents
           pure fs
    <|> do doc <- optDocumentation fname
           fs <- fieldBody doc Explicit
           atEnd indents
           pure fs
  where
    fieldBody : String -> PiInfo (Id FTerm) -> Rule (Id FField)
    fieldBody doc p
        = do b <- bounds $ do
                    rig <- multiplicity fname
                    ns <- sepBy1 (decoratedSymbol fname SymComma)
                            (fcBounds (decorate fname Function name
                               <|> (do b <- bounds (symbol SymUnderscore)
                                       fatalLoc {c = True} b.bounds "Fields have to be named")))
                    decoratedSymbol fname SymColon
                    ty <- typeExpr pdef fname indents
                    pure (rig, forget ns, ty)
             let (rig, ns, ty) = b.val
             node (FdField (boundToFC fname b) doc rig ns p ty)

parameters {auto fname : OriginDesc} {auto indents : IndentInfo}

  ifaceParam : Rule (Id FNames)
  ifaceParam
      = parens fname basicMultiBinder
    <|> do n <- fcBounds (decorate fname Bound name)
           ty <- node (TmInfer n.fc)
           node (BnNames erased (singleton n) ty)

  ifaceDecl : Rule (DeclOf Id)
  ifaceDecl
      = do  doc   <- optDocumentation fname
            vis   <- visibility fname
            col   <- column
            decoratedKeyword fname KwInterface
            commit
            cons   <- constraints fname indents
            n      <- decorate fname Typ name
            params <- many ifaceParam
            det    <- optional $ do
              b <- bounds $ decoratedSymbol fname SymBar
              mustWorkBecause b.bounds "Expected list of determining parameters" $
                sepBy1 (decoratedSymbol fname SymComma) (decorate fname Bound name)
            decoratedKeyword fname KwWhere
            dc <- optional (recordConstructor fname)
            body <- blockAfter col (topDecl fname)
            pure (DcInterface vis cons n doc params det dc body)

  implDecl : Rule (DeclOf Id)
  implDecl
      = do doc     <- optDocumentation fname
           visOpts <- many (visOpt fname)
           vis     <- getVisibility Nothing visOpts
           let opts = mapMaybe getRight visOpts
           col <- column
           option () (decoratedKeyword fname KwImplementation)
           iname  <- optional $ decoratedSymbol fname SymBracket
                             *> decorate fname Function name
                             <* decoratedSymbol fname SymBracketClose
           impls  <- implBinds fname indents (isJust iname)
           cons   <- constraints fname indents
           n      <- decorate fname Typ name
           params <- many (continue indents *> simpleExpr fname indents)
           nusing <- option [] $ decoratedKeyword fname KwUsing
                              *> forget <$> some (decorate fname Function name)
           body <- optional $ decoratedKeyword fname KwWhere *> blockAfter col (topDecl fname)
           atEnd indents
           pure $
              DcImplementation vis opts Single impls cons n params iname nusing body

  localClaim : Rule (DeclOf Id)
  localClaim
      = do doc     <- optDocumentation fname
           visOpts <- many (visOpt fname)
           vis     <- getVisibility Nothing visOpts
           let opts = mapMaybe getRight visOpts
           rig  <- multiplicity fname
           cls  <- tyDecls (decorate fname Function name)
                           doc fname indents
           pure $ DcClaim rig vis opts cls


  -- A Single binder with multiple names
  typedArg : Rule (Id FBinder)
  typedArg
      = do params <- parens fname $ pibindListName fname indents
           ns <- multiBinder params
           node (BnPi Explicit ns)
    <|> do decoratedSymbol fname SymBrace
           commit
           info <-
                    (pure  AutoImplicit <* decoratedKeyword fname KwAuto
                <|> (decoratedKeyword fname KwDefault *> DefImplicit <$> simpleExpr fname indents)
                <|> pure      Implicit)
           params <- pibindListName fname indents
           decoratedSymbol fname SymBraceClose
           ns <- multiBinder params
           node (BnPi info ns)

  ||| Record parameter, can be either a typed binder or a name
  ||| BNF:
  ||| recordParam := typedArg | name
  recordParam : Rule (Id FBinder)
  recordParam
      = typedArg
    <|> do n <- fcBounds (decoratedSimpleBinderUName fname)
           ty <- node (TmInfer n.fc)
           ns <- node (BnNames top (singleton n) ty)
           node (BnPi Explicit ns)

  -- A record without a where is a forward declaration
  recordBody : String -> WithDefault Visibility Private ->
               Maybe TotalReq ->
               Int ->
               Name ->
               List (Id FBinder) ->
               EmptyRule (DeclOf Id)
  recordBody doc vis mbtot col n params
      = do atEndIndent indents
           r <- node (RcLater n params)
           pure (DcRecord doc vis mbtot r)
    <|> do mustWork $ decoratedKeyword fname KwWhere
           opts <- dataOpts fname
           dcflds <- blockWithOptHeaderAfter col
                       (\ idt => recordConstructor fname <* atEnd idt)
                       fieldDecl
           r <- node (RcBody n params opts (fst dcflds) (snd dcflds))
           pure (DcRecord doc vis mbtot r)

  recordDecl : Rule (DeclOf Id)
  recordDecl
      = do doc         <- optDocumentation fname
           (vis,mbtot) <- dataVisOpt fname
           col         <- column
           decoratedKeyword fname KwRecord
           n       <- mustWork (decoratedDataTypeName fname)
           paramss <- many (continue indents >> recordParam)
           recordBody doc vis mbtot col n paramss

  ||| Parameter blocks
  ||| BNF:
  ||| paramDecls := 'parameters' (oldParamDecls | newParamDecls) indentBlockDefs
  paramDecls : Rule (DeclOf Id)
  paramDecls = do
           startCol <- column
           b1 <- decoratedKeyword fname KwParameters
           commit
           args <- Right <$> newParamDecls
               <|> Left <$> withWarning "DEPRECATED: old parameter syntax https://github.com/idris-lang/Idris2/issues/3447" oldParamDecls
           commit
           declarations <- nonEmptyBlockAfter startCol (topDecl fname)
           pure (DcParameters args (forget declarations))

    where
      oldParamDecls : Rule (List1 (Id FPlain))
      oldParamDecls
          = parens fname $ sepBy1 (decoratedSymbol fname SymComma) plainBinder

      newParamDecls : Rule (List1 (Id FBinder))
      newParamDecls = some typedArg


  definition : Rule (DeclOf Id)
  definition
      = do nd <- clause 0 Nothing fname indents
           pure (DcDef (singleton nd))

  operatorBindingKeyword : EmptyRule BindingModifier
  operatorBindingKeyword
    =   (decoratedKeyword fname KwAutobind >> pure Autobind)
    <|> (decoratedKeyword fname KwTypebind >> pure Typebind)
    <|> pure NotBinding

  fixDecl : Rule (Id FDecl)
  fixDecl
      = do vis <- exportVisibility fname
           binding <- operatorBindingKeyword
           b <- fcBounds (do fixity <- decorate fname Keyword $ fix
                             commit
                             prec <- decorate fname Keyword $ intLit
                             ops <- sepBy1 (decoratedSymbol fname SymComma) iOperator
                             pure (MkPFixityData vis binding fixity (fromInteger prec) ops)
                       )
           node (Declared b.fc (DcFixity b.val))

-- The compiler cannot infer the values for c1 and c2 so I had to write it
-- this way.
-- - Andre
cgDirectiveDecl : Rule (DeclOf Id)
cgDirectiveDecl
  = (>>=) {c1 = True, c2 = False} cgDirective $ \dir =>
      let (cg1, cg2) = span isAlphaNum dir
      in the (EmptyRule (DeclOf Id)) $ pure $
            DcDirective (CGAction cg1 (stripBraces (trimSpace cg2)))

-- A declaration's node, where its rule parsed it.
declared : OriginDesc => Rule (DeclOf Id) -> Rule (Id FDecl)
declared d = do b <- fcBounds d
                node (Declared b.fc b.val)

-- Declared at the top
-- topDecl : OriginDesc -> IndentInfo -> Rule (Id FDecl)
topDecl fname indents
      -- Specifically check if the user has attempted to use a reserved identifier to begin their declaration to give improved error messages.
      -- i.e. the claim "String : Type" is a parse error, but the underlying reason may not be clear to new users.
    = do id <- anyReservedIdent
         the (Rule (Id FDecl)) $ fatalLoc id.bounds "Cannot begin a declaration with a reserved identifier"
  <|> declared dataDecl
  <|> declared localClaim
  <|> declared (DcDirective <$> directive)
  <|> declared implDecl
  <|> declared definition
  <|> fixDecl
  <|> declared ifaceDecl
  <|> declared recordDecl
  <|> declared namespaceDecl
  <|> declared failDecls
  <|> declared mutualDecls
  <|> declared paramDecls
  <|> declared usingDecls
  <|> declared builtinDecl
  <|> declared runElabDecl
  <|> declared transformDecl
  <|> declared cgDirectiveDecl
      -- If the user tries to add import after some declarations, then show a more informative error.
  <|> do kw <- bounds $ keyword KwImport
         the (Rule (Id FDecl)) $ fatalLoc kw.bounds "Imports must go before any declarations or directives"
      -- If the user tried to begin a declaration with any other keyword, then show a more informative error.
  <|> do kw <- bounds anyKeyword
         the (Rule (Id FDecl)) $ fatalLoc kw.bounds "Keyword '\{keywordText kw.val}' is not a valid start to a declaration"
  <|> fatalError "Couldn't parse declaration"

export
import_ : OriginDesc -> IndentInfo -> Rule Import
import_ fname indents
    = do b <- bounds (do decoratedKeyword fname KwImport
                         reexp <- option False (decoratedKeyword fname KwPublic $> True)
                         ns <- decorate fname Module $ mustWork moduleIdent
                         nsAs <- option (miAsNamespace ns)
                                        (do decorate fname Keyword $ exactIdent Kas
                                            decorate fname Namespace $ mustWork namespaceId)
                         pure (reexp, ns, nsAs))
         atEnd indents
         (reexp, ns, nsAs) <- pure b.val
         pure (MkImport (boundToFC fname b) reexp ns nsAs)

-- A module's header: its documentation, its name and its imports.
moduleHead : OriginDesc -> EmptyRule Module
moduleHead fname
    = do b <- bounds (do doc    <- optDocumentation fname
                         nspace <- option (nsAsModuleIdent mainNS)
                                     (do decoratedKeyword fname KwModule
                                         decorate fname Module $ mustWork moduleIdent)
                         imports <- block (import_ fname)
                         pure (doc, nspace, imports))
         (doc, nspace, imports) <- pure b.val
         pure (MkModule (boundToFC fname b)
                        nspace imports doc [])

||| A module's header, which holds no syntax its tree decodes.
export
progHdr : OriginDesc -> EmptyRule (Read Module)
progHdr fname = (\mod, _ => Just mod) <$> moduleHead fname

||| A module, its declarations read off its parse tree.
export
prog : OriginDesc -> EmptyRule (Read Module)
prog fname
    = do mod <- moduleHead fname
         ds <- block (topDecl fname)
         pure (\t => (\parsed => { decls := parsed } mod) <$> declsIn ds t)
