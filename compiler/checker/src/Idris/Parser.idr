-- SPDX-License-Identifier: BSD-3-Clause
-- Copyright (c) 2020 Edwin Brady
module Idris.Parser

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

%default total

%hide Prelude.(>>)
%hide Prelude.(>>=)
%hide Core.Core.(>>)
%hide Core.Core.(>>=)
%hide Prelude.pure
%hide Core.Core.pure
%hide Prelude.(<*>)
%hide Core.Core.(<*>)

fcBounds : OriginDesc => Rule n r a -> Rule n r (WithFC a)
fcBounds a = (.withFC) <$> bounds a

-- What a bracket holds is read after the bracket, so below the bound.
parens : {0 b : Bool} -> BRule n True b a -> Rule n r a
parens p
  = pure id <* symbol SymParen
            <*> p
            <* symbol SymParenClose

curly : {0 b : Bool} -> BRule n True b a -> Rule n r a
curly p
  = pure id <* symbol SymBrace
            <*> p
            <* symbol SymBraceClose

simpleNamedArg : Rule n r Ident
simpleNamedArg
  = unqualifiedName
  <|> parens unqualifiedOperatorName

-- `%runElab` runs an elaborator script while the program is elaborated
-- (reading and writing files among what a script may do); this compiler
-- runs none, so the pragma is refused where it is read, before anything of
-- the script is parsed or run.
runElabRefused : String
runElabRefused = "unsupported: the pragma %runElab runs an elaborator script, and this compiler runs no elaborator script"

-- Some context for the parser
public export
record ParseOpts where
  constructor MkParseOpts
  eqOK : Bool -- = operator is parseable
  withOK : Bool -- = with applications are parseable

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

atom : OriginDesc -> Rule n r (Id FTerm)
atom fname
    = do x <- bounds $  exactIdent KType
         node (TmType (boundToFC fname x))
  <|> do x <- bounds $ name
         node (TmRef (boundToFC fname x) x.val)
  <|> do x <- bounds constant
         node (TmPrimVal (boundToFC fname x) x.val)
  <|> do x <- bounds $ symbol SymUnderscore
         node (TmImplicit (boundToFC fname x))
  <|> do x <- bounds $ symbol SymQuestion
         node (TmInfer (boundToFC fname x))
  <|> do x <- bounds $ holeName
         node (TmHole (boundToFC fname x) x.val)
  <|> do x <- bounds $  pragma fname KwMkWorld
         node (TmPrimVal (boundToFC fname x) WorldVal)
  <|> do x <- bounds $ pragma fname KwWorld
         node (TmPrimVal (boundToFC fname x) $ PrT WorldType)
  <|> do x <- bounds $ pragma fname KwSearch
         node (TmSearch (boundToFC fname x))

-- Expect a keyword, but if we get anything else it's a fatal error
commitKeyword : OriginDesc -> IndentInfo -> Keyword -> Rule n r ()
commitKeyword fname indents req
    = do mustContinue indents (Just (keywordText req))
         keyword req
          <|> the (Rule _ _ ()) (fatalError ("Expected '" ++ keywordText req ++ "'"))
         mustContinue indents Nothing

commitSymbol : OriginDesc -> Reserved -> Rule n r ()
commitSymbol fname req
    = symbol req
       <|> fatalError ("Expected '" ++ reservedText req ++ "'")

continueWith : IndentInfo -> Reserved -> Rule n r ()
continueWith indents req
    = mustContinue indents (Just (reservedText req)) *> symbol req

iOperator : Rule n r OpStr
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
applied : FC -> Id FTerm -> List ArgType -> EmptyRule n r (Id FTerm)
applied fc f args = build (foldlM step f args)
  where
    step : Id FTerm -> ArgType -> Build (Id FTerm)
    step g (UnnamedExpArg exp) = make (TmApp fc g exp)
    step g (UnnamedAutoArg imp) = make (TmAutoApp fc g imp)
    step g (NamedArg n imp) = make (TmNamedApp fc g n imp)
    step g (WithArg exp) = make (TmWithApp fc g exp)

-- A clause's left side with its `with` arguments applied.
withApplied : (Id FTerm, List (FC, Id FTerm)) -> EmptyRule n r (Id FTerm)
withApplied (f, args) = build (foldlM (\g, (fc, a) => make (TmWithApp fc g a)) f args)

-- The left side of a `with` clause written `_`: its parent's, every location
-- in it where the `_` is.
relocated : FC -> (Id FTerm, List (FC, Id FTerm)) -> EmptyRule n r (Id FTerm, List (FC, Id FTerm))
relocated vfc (f, args)
    = do f' <- node (TmRelocated vfc f)
         args' <- build (traverse (\(fc, a) => MkPair fc <$> make (TmRelocated vfc a)) args)
         pure (f', args')

-- A binder of several names, with its quantity and their type.
multiBinder : (RigCount, List1 (WithFC Name), Id FTerm) -> EmptyRule n r (Id FNames)
multiBinder (rig, ns, ty) = node (BnNames rig ns ty)

export
debugString : OriginDesc -> Rule n r (Id FTerm)
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

totalityOpt : OriginDesc -> Rule n r TotalReq
totalityOpt fname
    = (keyword KwPartial $> PartialOK)
  <|> (keyword KwTotal $> Total)
  <|> (keyword KwCovering $> CoveringOnly)

fnOpt : OriginDesc -> Rule n r (Id FOpt)
fnOpt fname
      = do x <- totalityOpt fname
           node (OpFn (Totality x))

multiplicity : OriginDesc -> EmptyRule n r RigCount
multiplicity fname
    = case !(optional $ intLit) of
        (Just 0) => pure erased
        (Just 1) => pure linear
        Nothing => pure top
        _ => fail "Invalid multiplicity (must be 0 or 1)"

||| The arrow used after an explicit binder
||| BNF:
||| bindSymbol := '->' | '=>'
bindSymbol : OriginDesc -> Rule n r (PiInfo (Id FTerm))
bindSymbol fname
    = (symbol SymArrow $> Explicit)
  <|> (symbol SymFatArrow $> AutoImplicit)

validPatternVar : Name -> EmptyRule n r ()
validPatternVar (UN Underscore) = pure ()
validPatternVar (UN (Basic i))
    = unless (lowerFirst i.text) $
        fail "Not a pattern variable"
validPatternVar _ = fail "Not a pattern variable"

getInitRange : List (WithBounds (Id FTerm)) -> EmptyRule n r (Id FTerm, Maybe (Id FTerm))
getInitRange [x] = pure (x.val, Nothing)
getInitRange [x,y] = pure (x.val, Just y.val)
getInitRange _ = fatalError "Invalid list range syntax"

visOption : OriginDesc ->  Rule n r Visibility
visOption fname
    = (keyword KwPublic *> keyword KwExport $> Public)
    -- If "public export" failed then we try to parse just "public" and emit an error message saying
    -- the user should use "public export"
  <|> (bounds (keyword KwPublic) >>= \x
    => the (Rule _ _ Visibility) (fatalLoc x.bounds
           #""public" keyword by itself is not an export modifier, did you mean "public export"?"#))
  <|> (keyword KwExport $> Export)
  <|> (keyword KwPrivate $> Private)

visibility : OriginDesc -> EmptyRule n r (WithDefault Visibility Private)
visibility fname
    = (specified <$> visOption fname)
  <|> pure defaulted

exportVisibility : OriginDesc -> EmptyRule n r (WithDefault Visibility Export)
exportVisibility fname
    = (specified <$> visOption fname)
  <|> pure defaulted

withFlags : OriginDesc -> EmptyRule n r (List WithFlag)
withFlags fname = many (Syntactic <$ pragma fname KwSyntactic)

-- A type constructor's type: a `Type` for each parameter, and `Type`. The
-- one `Type` is every one of them.
tyConType : OriginDesc -> FC -> List (WithBounds Name) -> EmptyRule n r (Id FTerm)
tyConType fname fc params
    = do ty <- node (TmType (virtualiseFC fc))
         build (foldlM (\rest, x => make (TmPi (boundToFC fname x) top Explicit Nothing ty rest))
                       ty (reverse params))

-- A constructor's argument in a simple data declaration: explicit or auto
-- implicit, as only these may be.
conArg : WithFC ArgType -> Maybe (FC, PiInfo (Id FTerm), Id FTerm)
conArg (MkFCVal fc (UnnamedExpArg x)) = Just (fc, Explicit, x)
conArg (MkFCVal fc (UnnamedAutoArg x)) = Just (fc, AutoImplicit, x)
conArg _ = Nothing -- with and named applications not allowed in simple ADTs

-- A constructor's type in a simple data declaration: its arguments, and the
-- type it returns.
dataConType : Id FTerm -> List (FC, PiInfo (Id FTerm), Id FTerm) -> EmptyRule n r (Id FTerm)
dataConType ret args
    = build (foldlM (\rest, (fc, info, x) => make (TmPi fc top info Nothing x rest))
                    ret (reverse args))

dataOpt : OriginDesc -> Rule n r DataOpt
dataOpt fname
    = ((exactIdent KnoHints) $> NoHints)
  <|> ((exactIdent KuniqueSearch) $> UniqueSearch)
  <|> (do b   <- bounds $ (exactIdent Ksearch)
          det <- mustWorkBecause b.bounds "Expected list of determining parameters" $
                   some (name)
          pure $ SearchBy det)
  <|> ((exactIdent Kexternal) $> External)
  <|> ((exactIdent KnoNewtype) $> NoNewtype)

dataOpts : OriginDesc -> EmptyRule n r (List DataOpt)
dataOpts fname = option [] $ do
  symbol SymBracket
  opts <- sepBy1 (symbol SymComma) (dataOpt fname)
  symbol SymBracketClose
  pure (forget opts)

-- a data declaration can have a visibility and an optional totality (#1404)
dataVisOpt : OriginDesc -> EmptyRule n r (WithDefault Visibility Private, Maybe TotalReq)
dataVisOpt fname
    = do { vis <- visOption   fname ; mbtot <- optional (totalityOpt fname) ; pure (specified vis, mbtot) }
  <|> do { tot <- totalityOpt fname ; vis <- visibility fname ; pure (vis, Just tot) }
  <|> pure (defaulted, Nothing)

stripBraces : String -> String
stripBraces str = pack (drop '{' (reverse (drop '}' (reverse (unpack str)))))
  where
    drop : Char -> List Char -> List Char
    drop c [] = []
    drop c (c' :: xs) = if c == c' then drop c xs else c' :: xs

onoff : Rule n r Bool
onoff
   = (exactIdent Kon $> True)
 <|> (exactIdent Koff $> False)
 <|> fail "expected 'on' or 'off'"

extension : Rule n r LangExt
extension
    = (exactIdent KElabReflection $> ElabReflection)
  <|> fail "expected 'ElabReflection'"

logLevel : OriginDesc -> Rule n r (Maybe LogLevel)
logLevel fname
  = (Nothing <$ (exactIdent Koff))
    <|> do topic <- optional (split ('.' ==) <$> simpleStr)
           lvl <- intLit
           pure (Just (mkLogLevel' topic (fromInteger lvl)))
    <|> fail "expected a log level"

fix : Rule n r Fixity
fix
    = (keyword KwInfixl $> InfixL)
  <|> (keyword KwInfixr $> InfixR)
  <|> (keyword KwInfix  $> Infix)
  <|> (keyword KwPrefix $> Prefix)

namespaceHead : OriginDesc -> Rule n r Namespace
namespaceHead fname
  = do keyword KwNamespace
       mustWork namespaceId

||| builtinDecl := 'builtin' builtinType name
builtinDecl : (fname : OriginDesc) => Rule n r (DeclOf Id)
builtinDecl
    = do pragma fname KwBuiltin
         commit
         t <- builtinType
         n <- name
         pure $ DcBuiltin t n

getVisibility : Maybe Visibility -> List (Either Visibility (Id FOpt)) ->
                EmptyRule n r Visibility
getVisibility Nothing [] = pure Private
getVisibility (Just vis) [] = pure vis
getVisibility Nothing (Left x :: xs) = getVisibility (Just x) xs
getVisibility (Just vis) (Left x :: xs)
   = fatalError "Multiple visibility modifiers"
getVisibility v (_ :: xs) = getVisibility v xs

recordConstructor : OriginDesc -> Rule n r (WithDocFC Name)
recordConstructor fname
  = do doc <- optDocumentation fname
       exactIdent Kconstructor
       n <- fcBounds $ mustWork $ dataConstructorName
       pure (doc :+ n)

autoImplicitField : OriginDesc -> IndentInfo -> Rule n r (PiInfo t)
autoImplicitField fname _ = AutoImplicit <$ keyword KwAuto

operatorBindingKeyword : (fname : OriginDesc) => EmptyRule n r BindingModifier
operatorBindingKeyword
  =   (keyword KwAutobind >> pure Autobind)
  <|> (keyword KwTypebind >> pure Typebind)
  <|> pure NotBinding

fixDecl : (fname : OriginDesc) => Rule n r (Id FDecl)
fixDecl
    = do vis <- exportVisibility fname
         binding <- operatorBindingKeyword
         b <- fcBounds (do fixity <-  fix
                           commit
                           prec <-  intLit
                           ops <- sepBy1 (symbol SymComma) iOperator
                           pure (MkPFixityData vis binding fixity (fromInteger prec) ops)
                     )
         node (Declared b.fc (DcFixity b.val))

cgDirectiveDecl : Rule n r (DeclOf Id)
cgDirectiveDecl
  = do dir <- cgDirective
       let (cg1, cg2) = span isAlphaNum dir
       pure (DcDirective (CGAction cg1 (stripBraces (trimSpace cg2))))

-- A declaration's node, where its rule parsed it.
declared : OriginDesc => Rule n r (DeclOf Id) -> Rule n r (Id FDecl)
declared d = do b <- fcBounds d
                node (Declared b.fc b.val)

export
import_ : OriginDesc -> IndentInfo -> Rule n r Import
import_ fname indents
    = do b <- bounds (do keyword KwImport
                         reexp <- option False (keyword KwPublic $> True)
                         ns <-  mustWork moduleIdent
                         nsAs <- option (miAsNamespace ns)
                                        (do exactIdent Kas
                                            mustWork namespaceId)
                         pure (reexp, ns, nsAs))
         atEnd indents
         (reexp, ns, nsAs) <- pure b.val
         pure (MkImport (boundToFC fname b) reexp ns nsAs)

-- A module's header: its documentation, its name and its imports.
moduleHead : OriginDesc -> EmptyRule n r Module
moduleHead fname
    = do b <- bounds (do doc    <- optDocumentation fname
                         nspace <- option (nsAsModuleIdent mainNS)
                                     (do keyword KwModule
                                         mustWork moduleIdent)
                         imports <- block (import_ fname)
                         pure (doc, nspace, imports))
         (doc, nspace, imports) <- pure b.val
         pure (MkModule (boundToFC fname b)
                        nspace imports doc [])

||| A module's header, which holds no syntax its tree decodes.
export
progHdr : OriginDesc -> EmptyRule n r (Read Module)
progHdr fname = (\mod, _ => Just mod) <$> moduleHead fname

-- The language's grammars name one another, and themselves: an expression
-- in brackets is an expression again, a `where` block holds declarations,
-- a declaration holds expressions. A grammar names one of these only once
-- it has read a token, through the box of them all at the bounds below its
-- own, so every grammar here is total by its types: what it names is had
-- at a smaller bound, and the one fixpoint below ties the box to them.
-- Each grammar it names through the box is a field here; every other is
-- named in place, before or after a token, and none of them names itself.
%prefix_record_projections off

||| The grammars the language's grammars name. `Grammars False n` holds
||| each at bound `n`, run where the parse stands; `Grammars True n` holds
||| each as a grammar at bound `n` names it, only once it has read a token,
||| so below `n`.
record Grammars (read : Bool) (n : Nat) where
  constructor MkGrammars
  expr : ParseOpts -> OriginDesc -> IndentInfo -> Rule n read (Id FTerm)
  typeExpr : ParseOpts -> OriginDesc -> IndentInfo -> Rule n read (Id FTerm)
  opExpr : ParseOpts -> OriginDesc -> IndentInfo -> Rule n read (Id FTerm)
  opExprBase : ParseOpts -> OriginDesc -> IndentInfo -> Rule n read (Id FTerm)
  simpleExpr : OriginDesc -> IndentInfo -> Rule n read (Id FTerm)
  simplerExpr : OriginDesc -> IndentInfo -> Rule n read (Id FTerm)
  nestedDpair : OriginDesc -> WithBounds () -> IndentInfo -> Rule n read (Id FTerm)
  clause : (withArgs : Nat) -> IMaybe (isSucc withArgs) (Id FTerm, List (FC, Id FTerm)) ->
           OriginDesc -> IndentInfo -> Rule n read (Id FClause)
  topDecl : OriginDesc -> IndentInfo -> Rule n read (Id FDecl)

%prefix_record_projections on

-- Each of the grammars as a grammar at bound `n` names it: the grammar the
-- box holds where the parse then stands, below `n`.
reentered : Box (Grammars False) n -> Grammars True n
reentered box
    = MkGrammars
        (\q, fname, indents => call box (\g => g.expr q fname indents))
        (\q, fname, indents => call box (\g => g.typeExpr q fname indents))
        (\q, fname, indents => call box (\g => g.opExpr q fname indents))
        (\q, fname, indents => call box (\g => g.opExprBase q fname indents))
        (\fname, indents => call box (\g => g.simpleExpr fname indents))
        (\fname, indents => call box (\g => g.simplerExpr fname indents))
        (\fname, start, indents => call box (\g => g.nestedDpair fname start indents))
        (\withArgs, lhs, fname, indents => call box (\g => g.clause withArgs lhs fname indents))
        (\fname, indents => call box (\g => g.topDecl fname indents))

-- The language's grammars at bound `n`, each naming the grammars it names
-- once it has read a token as `again` holds them.
parameters {0 n : Nat} (again : Grammars True n)
  mutual
    whereBlock : OriginDesc -> Int -> Rule n r (List (Id FDecl))
    whereBlock fname col
        = do keyword KwWhere
             blockAfter col (again.topDecl fname)

    appExpr : ParseOpts -> OriginDesc -> IndentInfo -> Rule n r (Id FTerm)
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
      <|> do b <- fcBounds (MkPair <$> fcBounds iOperator <*> again.expr pdef fname indents)
             (op, arg) <- pure b.val
             node (TmPrefixOp b.fc op arg)
      <|> fail "Expected 'case', 'if', 'do', application or operator expression"

    argExpr : ParseOpts -> OriginDesc -> IndentInfo -> Rule n True (List ArgType)
    argExpr q fname indents
        = do continue indents
             arg <- again.simpleExpr fname indents
             pure [UnnamedExpArg arg]
      <|> do continue indents
             braceArgs fname indents
      <|> if withOK q
             then do continue indents
                     symbol SymBar
                     arg <- again.expr ({withOK := False} q) fname indents
                     pure [WithArg arg]
             else fail "| not allowed here"
      where
        underscore : FC -> EmptyRule n True ArgType
        underscore fc = NamedArg (UN Underscore) <$> node (TmImplicit fc)

        braceArgs : OriginDesc -> IndentInfo -> Rule n True (List ArgType)
        braceArgs fname indents
          = do start <- bounds (symbol SymBrace)
               mustWork $ do
                 list <- sepBy (symbol SymComma)
                          $ do x <- bounds (UN . Basic <$> simpleNamedArg)
                               let fc = boundToFC fname x
                               (do tm <- symbol SymEquals *> again.typeExpr pdef fname indents
                                   pure (NamedArg x.val tm))
                                 <|> (NamedArg x.val <$> node (TmRef fc x.val))
                 matchAny <- option [] (if isCons list then
                                           do symbol SymComma
                                              x <- bounds (symbol SymUnderscore)
                                              u <- underscore (boundToFC fname x)
                                              pure [u]
                                        else fail "non-empty list required")
                 end <- bounds (symbol SymBraceClose)
                 matchAny <- if isNil list
                                then do u <- underscore (boundToFC fname (mergeBounds start end))
                                        pure [u]
                                else pure matchAny
                 pure $ matchAny ++ list

          <|> do symbol SymAtBrace
                 commit
                 tm <- again.typeExpr pdef fname indents
                 symbol SymBraceClose
                 pure [UnnamedAutoArg tm]

    with_ : OriginDesc -> IndentInfo -> Rule n r (Id FTerm)
    with_ fname indents
        = do b <- bounds (do keyword KwWith
                             commit
                             ns <- singleName <|> nameList
                             end <- location
                             rhs <- again.expr pdef fname indents
                             pure (ns, rhs))
             (ns, rhs) <- pure b.val
             node (TmWithNames (boundToFC fname b) ns rhs)
      where
        singleName : Rule n True (List (FC, Name))
        singleName = do
          n <- bounds name
          pure [(boundToFC fname n, n.val)]

        nameList : Rule n True (List (FC, Name))
        nameList = do
          symbol SymBracket
          commit
          ns <- sepBy1 (symbol SymComma) (bounds name)
          symbol SymBracketClose
          pure (map (\ n => (boundToFC fname n, n.val)) $ forget ns)

    -- The different kinds of operator bindings `x : ty` for typebind
    -- x <- e and x : ty <- e for autobind
    opBinderTypes : OriginDesc -> IndentInfo -> WithBounds (Id FTerm) -> Rule n r (OperatorLHSInfo (Id FTerm))
    opBinderTypes fname indents boundName =
             do symbol SymColon
                ty <- again.typeExpr pdef fname indents
                symbol SymLeftArrow
                exp <- again.expr pdef fname indents
                pure (BindExplicitType boundName.val ty exp)
         <|> do symbol SymLeftArrow
                exp <- again.expr pdef fname indents
                pure (BindExpr boundName.val exp)
         <|> do symbol SymColon
                ty <- again.typeExpr pdef fname indents
                pure (BindType boundName.val ty)

    opBinder : OriginDesc -> IndentInfo -> Rule n True (OperatorLHSInfo (Id FTerm))
    opBinder fname indents
        = do boundName <- bounds (again.expr plhs fname indents)
             opBinderTypes fname indents boundName

    autobindOp : ParseOpts -> OriginDesc -> IndentInfo -> Rule n r (Id FTerm)
    autobindOp q fname indents
        = do b <- fcBounds $ do
               binder <- fcBounds $ parens (opBinder fname indents)
               continue indents
               op <- fcBounds iOperator
               commit
               e <- again.expr q fname indents
               pure (binder, op, e)
             node (TmOp b.fc (fst b.val) (fst (snd b.val)) (snd (snd b.val)))

    opExprBase : ParseOpts -> OriginDesc -> IndentInfo -> Rule n r (Id FTerm)
    opExprBase q fname indents
        = do l <- bounds (appExpr q fname indents)
             (if eqOK q
                 then do rhs <- bounds (continue indents
                                    *> symbol SymEquals
                                    *> again.opExprBase q fname indents)
                         node $
                           let fc = boundToFC fname (mergeBounds l rhs)
                               opFC = virtualiseFC fc -- already been highlighted: we don't care
                           in TmOp fc (map NoBinder l.withFC)
                                      (MkFCVal opFC (OpSymbols $ knownUN KEquals))
                                      rhs.val
                 else fail "= not allowed")
               <|>
               (do b <- bounds $ do
                          continue indents
                          op <- fcBounds iOperator
                          let root = case op.val of
                                          OpSymbols n => knownRoot n
                                          Backticked _ => Nothing
                          e <- case root of
                                 Just KDollar => again.typeExpr q fname indents
                                 _ => again.expr q fname indents
                          pure (op, e)
                   (op, rhs) <- pure b.val
                   let fc = boundToFC fname (mergeBounds l b)
                   node (TmOp fc (map NoBinder l.withFC) op rhs))
                 <|> pure l.val

    opExpr : ParseOpts -> OriginDesc -> IndentInfo -> Rule n r (Id FTerm)
    opExpr q fname indents = autobindOp q fname indents
                         <|> opExprBase q fname indents

    dpairType : OriginDesc -> WithBounds t -> IndentInfo -> Rule n r (Id FTerm)
    dpairType fname start indents
        = do loc <- bounds (do x <- userName
                               symbol SymColon
                               ty <- again.typeExpr pdef fname indents
                               pure (x, ty))
             (x, ty) <- pure loc.val
             op <- bounds (symbol SymStarStar)
             rest <- bounds (again.nestedDpair fname (ignore loc) indents <|> again.typeExpr pdef fname indents)
             var <- node (TmRef (boundToFC fname loc) x)
             node (TmDPair (boundToFC fname (mergeBounds start rest))
                           (boundToFC fname op)
                           var
                           ty
                           rest.val)

    nestedDpair : OriginDesc -> WithBounds () -> IndentInfo -> Rule n r (Id FTerm)
    nestedDpair fname start indents
        = dpairType fname start indents
      <|> do l <- expr pdef fname indents
             loc <- bounds (symbol SymStarStar)
             rest <- bounds (again.nestedDpair fname loc indents <|> again.expr pdef fname indents)
             imp <- node (TmImplicit (boundToFC fname (mergeBounds start rest)))
             node (TmDPair (boundToFC fname (mergeBounds start rest))
                           (boundToFC fname loc)
                           l
                           imp
                           rest.val)

    bracketedExpr : OriginDesc -> WithBounds t -> IndentInfo -> Rule n True (Id FTerm)
    bracketedExpr fname s indents
        -- left section. This may also be a prefix operator, but we'll sort
        -- that out when desugaring: if the operator is infix, treat it as a
        -- section otherwise treat it as prefix
        = do b <- bounds (do op <- fcBounds iOperator
                             e <- again.expr pdef fname indents
                             continueWith indents SymParenClose
                             pure (op, e))
             (op, e) <- pure b.val
             let fc = boundToFC fname (mergeBounds s b)
             node (TmSectionL fc op e)
      <|> do  -- (.y.z)  -- section of projection (chain)
             b <- bounds $ forget <$> some (bounds postfixProj)
             symbol SymParenClose
             let projs = map (\ proj => (boundToFC fname proj, proj.val)) b.val
             node $ TmPostfixAppPartial (boundToFC fname b) projs
        -- unit type/value
      <|> do b <- bounds (continueWith indents SymParenClose)
             node (TmUnit (boundToFC fname (mergeBounds s b)))
        -- dependent pairs with type annotation (so, the type form)
      <|> do dpairType fname s indents <* symbol SymParenClose
      <|> do e <- bounds (again.typeExpr pdef fname indents)
             -- dependent pairs with no type annotation
             (do loc <- bounds (symbol SymStarStar)
                 rest <- bounds ((again.nestedDpair fname loc indents <|> again.expr pdef fname indents) <* symbol SymParenClose)
                 imp <- node (TmImplicit (boundToFC fname (mergeBounds s rest)))
                 node (TmDPair (boundToFC fname (mergeBounds s rest))
                               (boundToFC fname loc)
                               e.val
                               imp
                               rest.val)) <|>
               -- right sections
               ((do op <- bounds (fcBounds iOperator <* symbol SymParenClose)
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

    listRange : OriginDesc -> WithBounds t -> IndentInfo -> List (WithBounds (Id FTerm)) -> Rule n True (Id FTerm)
    listRange fname s indents xs
        = do b <- bounds (symbol SymBracketClose)
             let fc = boundToFC fname (mergeBounds s b)
             rstate <- getInitRange xs
             node (TmRangeStream fc (fst rstate) (snd rstate))
      <|> do y <- bounds (again.expr pdef fname indents <* symbol SymBracketClose)
             let fc = boundToFC fname (mergeBounds s y)
             rstate <- getInitRange xs
             node (TmRange fc (fst rstate) (snd rstate) y.val)

    listExpr : OriginDesc -> WithBounds () -> IndentInfo -> Rule n True (Id FTerm)
    listExpr fname s indents
        = do b <- bounds (do ret <- again.expr pnowith fname indents
                             symbol SymBar
                             conds <- sepBy1 (symbol SymComma) (doAct fname indents)
                             symbol SymBracketClose
                             pure (ret, conds))
             (ret, conds) <- pure b.val
             node (TmComprehension (boundToFC fname (mergeBounds s b)) ret (concat conds))
      <|> do xs <- option [] $ do
                       hd <- again.expr pdef fname indents
                       tl <- many $ do b <- bounds (symbol SymComma)
                                       x <- mustWork $ again.expr pdef fname indents
                                       pure (x <$ b)
                       pure ((hd <$ s) :: tl)
             (do symbol SymDotDot
                 listRange fname s indents xs)
               <|> (do b <- bounds (symbol SymBracketClose)
                       node $
                         let fc = boundToFC fname (mergeBounds s b)
                             nilFC = if null xs then fc else boundToFC fname b
                         in TmList fc nilFC (map (\ t => (boundToFC fname t, t.val)) xs))

    snocListExpr : OriginDesc -> WithBounds () -> IndentInfo -> Rule n True (Id FTerm)
    snocListExpr fname s indents
        = {- TODO: comprehension -}
          do mHeadTail <- optional $ do
               hd <- many $ do x <- again.expr pdef fname indents
                               b <- bounds (symbol SymComma)
                               pure (x <$ b)
               tl <- again.expr pdef fname indents
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
    nonEmptyTuple : OriginDesc -> WithBounds t -> IndentInfo -> Id FTerm -> Rule n r (Id FTerm)
    nonEmptyTuple fname s indents e
        = do vals <- some $ do b <- bounds (symbol SymComma)
                               exp <- optional (again.typeExpr pdef fname indents)
                               pure (boundToFC fname b, exp)
             end <- continueWith indents SymParenClose
             comps <- build (traverse component (numbered vals))
             let terms = map (either id id . snd) comps
             let lefts = e :: init terms
             let fcs = forget (map fst comps)
             pairs <- build (foldlM (\acc, (f, l) => make (TmPair f l acc))
                                    (last terms) (reverse (zip fcs lefts)))
             let vars = mapMaybe (\(fc, c) => MkPair fc <$> getRight c) (forget comps)
             infs <- build (traverse (\(fc, v) => (\i => (fc, v, i)) <$> make (TmInfer (virtualiseFC fc)))
                                     vars)
             build (foldlM bindLeftOut pairs (reverse infs))
      where
        -- The section's binder for one component it leaves out, around what
        -- is built so far: the component's variable, at its inferred type.
        bindLeftOut : Id FTerm -> (FC, Id FTerm, Id FTerm) -> Build (Id FTerm)
        bindLeftOut acc (fc, v, i) = make (TmLam (virtualiseFC fc) top Explicit v i acc)

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
    tuple : OriginDesc -> WithBounds t -> IndentInfo -> Id FTerm -> Rule n r (Id FTerm)
    tuple fname s indents e
       =   nonEmptyTuple fname s indents e
       <|> do end <- bounds (continueWith indents SymParenClose)
              node (TmBracketed (boundToFC fname (mergeBounds s end)) e)

    simpleExpr : OriginDesc -> IndentInfo -> Rule n r (Id FTerm)
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

    simplerExpr : OriginDesc -> IndentInfo -> Rule n r (Id FTerm)
    simplerExpr fname indents
        = do b <- bounds (do x <- bounds (userName)
                             symbol SymAt
                             commit
                             expr <- again.simpleExpr fname indents
                             pure (x, expr))
             (x, expr) <- pure b.val
             node (TmAs (boundToFC fname b) (boundToFC fname x) x.val expr)
      <|> do b <- bounds $ do
                    mns <- namespacedSymbol SymIdiom SymDotIdiom
                    t   <- again.expr pdef fname indents
                    symbol SymIdiomClose
                    pure (t, mns)
             node (TmIdiom (boundToFC fname b) (snd b.val) (fst b.val))
      <|> atom fname
      <|> record_ fname indents
      <|> singlelineStr pdef fname indents
      <|> multilineStr pdef fname indents
      <|> do b <- bounds $ do
                    symbol SymDotParen
                    commit
                    t <- again.typeExpr pdef fname indents
                    symbol SymParenClose
                    pure t
             node (TmDotted (boundToFC fname b) b.val)
      <|> do b <- bounds $ do
                    symbol SymQuoteParen
                    t <- again.typeExpr pdef fname indents
                    symbol SymParenClose
                    pure t
             node (TmQuote (boundToFC fname b) b.val)
      <|> do b <- bounds $ do
                    symbol SymQuoteBrace
                    t <- name
                    symbol SymBraceClose
                    pure t
             node (TmQuoteName (boundToFC fname b) b.val)
      <|> do b <- bounds $ do
                    symbol SymQuoteBracket
                    ts <- nonEmptyBlock (again.topDecl fname)
                    symbol SymBracketClose
                    pure ts
             node (TmQuoteDecl (boundToFC fname b) (forget b.val))
      <|> do b <- bounds (symbol SymTilde *> again.simplerExpr fname indents)
             node (TmUnquote (boundToFC fname b) b.val)
      <|> do start <- bounds (symbol SymParen)
             bracketedExpr fname start indents
      <|> do start <- bounds (symbol SymSnocBracket)
             snocListExpr fname start indents
      <|> do start <- bounds (symbol SymListBracket <|> symbol SymBracket)
             listExpr fname start indents
      <|> do b <- bounds (symbol SymBang *> again.simpleExpr fname indents)
             node (TmBang (virtualiseFC $ boundToFC fname b) b.val)
      <|> do b <- bounds $ do pragma fname KwLogging
                              topic <- optional (split (('.') ==) <$> simpleStr)
                              lvl   <- intLit
                              e     <- again.expr pdef fname indents
                              pure (MkPair (mkLogLevel' topic (integerToNat lvl)) e)
             (lvl, e) <- pure b.val
             node (TmUnifyLog (boundToFC fname b) lvl e)
      <|> withWarning "DEPRECATED: trailing lambda. Use a $ or parens"
          (lam fname indents)

    bindList : OriginDesc -> IndentInfo ->
               Rule n True (List (RigCount, WithBounds (Id FTerm), Id FTerm, PiInfo (Id FTerm)))
    bindList fname indents
        = forget <$> sepBy1 (symbol SymComma) (explicitBind <|> implicitBind)
      where
        explicitBind : Rule n True (RigCount, WithBounds (Id FTerm), Id FTerm, PiInfo (Id FTerm))
        explicitBind = do
          rig <- multiplicity fname
          pat <- bounds (again.simpleExpr fname indents)
          ty <- (symbol SymColon *> again.opExpr pdef fname indents)
                  <|> node (TmInfer (boundToFC fname pat))
          pure (rig, pat, ty, Explicit)

        implicitBind : Rule n True (RigCount, WithBounds (Id FTerm), Id FTerm, PiInfo (Id FTerm))
        implicitBind = curly $ do
          rig <- multiplicity fname
          pat <- bounds (again.simpleExpr fname indents)
          ty <- (symbol SymColon *> again.opExpr pdef fname indents)
                  <|> node (TmInfer (boundToFC fname pat))
          pure (rig, pat, ty, Implicit)

    ||| A list of names bound to the same type
    ||| BNF:
    ||| pibindListName := qty name (, name)* ':' typeExpr
    pibindListName : OriginDesc -> IndentInfo ->
                     Rule n r (RigCount, List1 (WithFC Name), Id FTerm)
    pibindListName fname indents
         = do rig <- multiplicity fname
              ns <- sepBy1 (symbol SymComma)
                           (fcBounds binderName)
              symbol SymColon
              ty <- again.typeExpr pdef fname indents
              atEnd indents
              pure (rig, ns, ty)
      where
        -- _ gets treated specially here, it means "I don't care about the name"
        binderName : Rule n r Name
        binderName = userName
                 <|> (UN <$> symbol SymUnderscore $> Underscore)

    ||| An explicit pi-type
    ||| BNF:
    ||| explicitPi := '(' pibindListName ')' bindSymbol typeExpr
    explicitPi : OriginDesc -> IndentInfo -> Rule n r (Id FTerm)
    explicitPi fname indents
        = do b <- fcBounds (do
                 bs <- bounds $ parens $ pibindListName fname indents
                 exp <- mustWorkBecause bs.bounds "Cannot return a named argument"
                          $ bindSymbol fname
                 scope <- mustWork $ again.typeExpr pdef fname indents
                 pure (exp, bs.val, scope))
             let (exp, bound, scope) = b.val
             ns <- multiBinder bound
             bd <- node (BnPi exp ns)
             node (TmNewPi b.fc bd scope)

    ||| An auto-implicit pi-type
    ||| BNF:
    ||| autoImplicitPi := '{' 'auto' pibindListName '}' '->' typeExpr
    autoImplicitPi : OriginDesc -> IndentInfo -> Rule n r (Id FTerm)
    autoImplicitPi fname indents
        = do b <- fcBounds (do
                 bs <- bounds $ curly $ do
                        keyword KwAuto
                        commit
                        binders <- pibindListName fname indents
                        pure binders
                 mustWorkBecause bs.bounds "Cannot return an auto implicit argument"
                   $ symbol SymArrow
                 scope <- mustWork $ again.typeExpr pdef fname indents
                 pure (bs.val, scope))
             let (bound, scope) = b.val
             ns <- multiBinder bound
             bd <- node (BnPi AutoImplicit ns)
             node (TmNewPi b.fc bd scope)

    ||| An default implicit pi-type
    ||| BNF:
    ||| defaultImplicitPi := '{' 'default' simpleExpr pibindListName '}' '->' typeExpr
    defaultImplicitPi : OriginDesc -> IndentInfo -> Rule n r (Id FTerm)
    defaultImplicitPi fname indents
        = do b <- fcBounds (do
                 bs <- bounds $ curly $ do
                        keyword KwDefault
                        commit
                        t <- again.simpleExpr fname indents
                        binders <- pibindListName fname indents
                        pure (t, binders)
                 mustWorkBecause bs.bounds "Cannot return a default implicit argument"
                   $ symbol SymArrow
                 scope <- mustWork $ again.typeExpr pdef fname indents
                 pure (bs.val, scope))
             let ((t, bound), scope) = b.val
             ns <- multiBinder bound
             bd <- node (BnPi (DefImplicit t) ns)
             node (TmNewPi b.fc bd scope)

    ||| Forall definition that automatically binds the names
    ||| BNF:
    ||| forall_ := 'forall' name (, name)* '.' typeExpr
    forall_ : OriginDesc -> IndentInfo -> Rule n r (Id FTerm)
    forall_ fname indents
        = do b <- fcBounds (do
                 bs <- bounds $ do
                        keyword KwForall
                        commit
                        ns <- sepBy1 (symbol SymComma)
                                     (fcBounds (userName))
                        pure ns
                 b' <- bounds peek
                 mustWorkBecause b'.bounds "Expected ',' or '.'"
                   $ (exactSymbol KDot)
                 scope <- mustWork $ again.typeExpr pdef fname indents
                 pure (bs.val, scope))
             node (TmForall b.fc (fst b.val) (snd b.val))

    ||| implicit pi-type
    ||| BNF:
    ||| implicitPi := '{' pibindListName '}' '->' typeExpr
    implicitPi : OriginDesc -> IndentInfo -> Rule n r (Id FTerm)
    implicitPi fname indents
        = do b <- fcBounds (do
                 bs <- bounds $ curly $ pibindListName fname indents
                 mustWorkBecause bs.bounds "Cannot return an implicit argument"
                  $ symbol SymArrow
                 scope <- mustWork $ again.typeExpr pdef fname indents
                 pure (bs.val, scope))
             let (bound, scope) = b.val
             ns <- multiBinder bound
             bd <- node (BnPi Implicit ns)
             node (TmNewPi b.fc bd scope)

    lam : OriginDesc -> IndentInfo -> Rule n r (Id FTerm)
    lam fname indents
        = do symbol SymBackslash
             commit
             switch <- optional (bounds $ keyword KwCase)
             case switch of
               Nothing => continueLamImpossible <|> continueLam
               Just endCase => continueLamCase endCase

       where
         -- A lambda matching its argument with `alts`: its variable is
         -- written twice, as the lambda's pattern and as what the case
         -- matches.
         lamCase : (fcCase : FC) -> (fc : FC) -> List (Id FClause) -> EmptyRule n True (Id FTerm)
         lamCase fcCase fc alts
             = do var <- node (TmRef fcCase (MN (known Klcase) 0))
                  inf <- node (TmInfer fcCase)
                  body <- node (TmCase (virtualiseFC fc) [] var alts)
                  node (TmLam fcCase top Explicit var inf body)

         continueLamImpossible : Rule n True (Id FTerm)
         continueLamImpossible = do
             lhs <- bounds (again.opExpr plhs fname indents)
             end <- bounds (keyword KwImpossible)
             let fc = boundToFC fname (mergeBounds lhs end)
             alt <- node (ClImpossible fc lhs.val)
             lamCase (boundToFC fname lhs) fc [alt]

         bindOne : Id FTerm -> (RigCount, WithBounds (Id FTerm), Id FTerm, PiInfo (Id FTerm)) ->
                   Build (Id FTerm)
         bindOne scope (rig, pat, ty, icit) = make (TmLam (boundToFC fname pat) rig icit pat.val ty scope)

         continueLam : Rule n True (Id FTerm)
         continueLam = do
             binders <- bindList fname indents
             commitSymbol fname SymFatArrow
             mustContinue indents Nothing
             scope <- again.typeExpr pdef fname indents
             build (foldlM bindOne scope (reverse binders))

         continueLamCase : WithBounds () -> Rule n True (Id FTerm)
         continueLamCase endCase = do
             b <- bounds (forget <$> nonEmptyBlock (caseAlt fname))
             lamCase (virtualiseFC $ boundToFC fname endCase) (boundToFC fname b) b.val

    letBlock : OriginDesc -> IndentInfo -> Rule n True (WithBounds (Either LetBinder LetDecl))
    letBlock fname indents = bounds (letBinder <||> letDecl) where

      letBinder : Rule n True LetBinder
      letBinder = do s <- bounds (MkPair <$> multiplicity fname <*> again.expr plhs fname indents)
                     (rig, pat) <- pure s.val
                     ty <- (symbol SymColon *> again.typeExpr (pnoeq pdef) fname indents)
                             <|> node (TmImplicit (virtualiseFC $ boundToFC fname s))
                     (symbol SymEquals <|> symbol SymAssign)
                     val <- again.typeExpr pnowith fname indents
                     alts <- block (patAlt fname)
                     pure (MkLetBinder rig pat ty val alts)

      letDecl : Rule n True LetDecl
      letDecl = forget <$> nonEmptyBlock (try . again.topDecl fname)

    let_ : OriginDesc -> IndentInfo -> Rule n r (Id FTerm)
    let_ fname indents
        = do keyword KwLet
             commit
             res <- nonEmptyBlock (letBlock fname)
             commitKeyword fname indents KwIn
             scope <- again.typeExpr pdef fname indents
             build (mkLets fname res scope)

    case_ : OriginDesc -> IndentInfo -> Rule n r (Id FTerm)
    case_ fname indents
        = do opts <- many (fnDirectOpt fname)
             b <- bounds (do keyword KwCase
                             scr <- again.expr pdef fname indents
                             mustWork (commitKeyword fname indents KwOf)
                             alts <- block (caseAlt fname)
                             pure (scr, alts))
             (scr, alts) <- pure b.val
             node (TmCase (virtualiseFC $ boundToFC fname b) opts scr alts)


    caseAlt : OriginDesc -> IndentInfo -> Rule n True (Id FClause)
    caseAlt fname indents
        = do lhs <- bounds (again.opExpr plhs fname indents)
             caseRHS fname lhs indents lhs.val

    caseRHS : OriginDesc -> WithBounds t -> IndentInfo -> Id FTerm -> Rule n r (Id FClause)
    caseRHS fname start indents lhs
        = do rhs <- bounds $ do
                      symbol SymFatArrow
                      mustContinue indents Nothing
                      again.typeExpr pdef fname indents
             atEnd indents
             let fc = boundToFC fname (mergeBounds start rhs)
             node (ClPattern fc lhs rhs.val [])
      <|> do end <- bounds (keyword KwImpossible)
             atEnd indents
             node (ClImpossible (boundToFC fname (mergeBounds start end)) lhs)
      <|> fatalError ("Expected '=>' or 'impossible'")

    if_ : OriginDesc -> IndentInfo -> Rule n r (Id FTerm)
    if_ fname indents
        = do b <- bounds (do keyword KwIf
                             commit
                             x <- again.expr pdef fname indents
                             commitKeyword fname indents KwThen
                             t <- again.typeExpr pdef fname indents
                             commitKeyword fname indents KwElse
                             e <- again.typeExpr pdef fname indents
                             pure (x, t, e))
             mustWork $ atEnd indents
             (x, t, e) <- pure b.val
             node (TmIfThenElse (boundToFC fname b) x t e)

    record_ : OriginDesc -> IndentInfo -> Rule n r (Id FTerm)
    record_ fname indents
        = do
             b <- (
                 withWarning oldSyntaxWarning (
                   bounds (do
                     keyword KwRecord
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

        -- The braces of an update, read after `record` or where the update
        -- begins.
        body : {0 rd : Bool} -> Bool -> Rule n rd (List1 (Id FUpdate))
        body kw = curly $ do
          commit
          sepBy1 (symbol SymComma) (field kw fname indents)

    field : Bool -> OriginDesc -> IndentInfo -> Rule n r (Id FUpdate)
    field kw fname indents
        = do path <- [| fieldPart (name) :: many (fieldPart recFieldCompat) |]
             upd <- (ifThenElse kw (symbol SymEquals) (symbol SymAssign) $> UpSet)
                        <|>
                    (symbol SymUpdate $> UpApply)
             val <- again.typeExpr plhs fname indents
             node (upd path val)
      where
        fieldName : Name -> Maybe Ident
        fieldName (UN (Basic s)) = Just s
        fieldName (UN (Field s)) = Just s
        fieldName _ = Nothing

        -- A path names each field by its identifier, so a name that is no
        -- field's (a qualified one) is refused here, where it is written.
        fieldPart : {0 rd : Bool} -> Rule n rd Name -> Rule n rd Ident
        fieldPart rule
            = do n <- rule
                 the (EmptyRule _ _ Ident) $ case fieldName n of
                      Just i => pure i
                      Nothing => fail "Expected a record field name"

        -- this allows the dotted syntax .field
        -- but also the arrowed syntax ->field for compatibility with Idris 1
        recFieldCompat : {0 rd : Bool} -> Rule n rd Name
        recFieldCompat = postfixProj
                    <|> (symbol SymArrow
                         *> name)

    rewrite_ : OriginDesc -> IndentInfo -> Rule n r (Id FTerm)
    rewrite_ fname indents
        = do b <- bounds (do keyword KwRewrite
                             rule <- again.expr pdef fname indents
                             commitKeyword fname indents KwIn
                             tm <- again.typeExpr pdef fname indents
                             pure (rule, tm))
             (rule, tm) <- pure b.val
             node (TmRewrite (boundToFC fname b) rule tm)

    doBlock : OriginDesc -> IndentInfo -> Rule n r (Id FTerm)
    doBlock fname indents
        = do b <- bounds $ keyword KwDo *> block (doAct fname)
             commit
             node (TmDoBlock (virtualiseFC $ boundToFC fname b) Nothing (concat b.val))
      <|> do nsdo <- bounds namespacedIdent
             -- TODO: need to attach metadata correctly here
             the (EmptyRule _ _ (Id FTerm)) $ case nsdo.val of
                  (ns, ident) =>
                     if ident == known Kdo
                        then do commit
                                actions <- Core.bounds (block (doAct fname))
                                let fc = virtualiseFC $
                                         boundToFC fname (mergeBounds nsdo actions)
                                node (TmDoBlock fc ns (concat actions.val))
                        else fail "Not a namespaced 'do'"

    doAct : OriginDesc -> IndentInfo -> Rule n True (List (Id FDo))
    doAct fname indents
        = do b <- bounds (do rig <- multiplicity fname
                             n <- bounds (name <|> UN Underscore <$ symbol SymUnderscore)
                             -- If the name doesn't begin with a lower case letter, we should
                             -- treat this as a pattern, so fail
                             validPatternVar n.val
                             ty <- optional (symbol SymColon *> again.typeExpr (pnoeq pdef) fname indents)
                             symbol SymLeftArrow
                             val <- again.expr pdef fname indents
                             pure (n, rig, ty, val))
             atEnd indents
             let (n, rig, ty, val) = b.val
             st <- node (StBind (boundToFC fname b) (boundToFC fname n) n.val rig ty val)
             pure [st]
      <|> do keyword KwLet
             commit
             res <- nonEmptyBlock (letBlock fname)
             do b <- bounds (keyword KwIn)
                fatalLoc {c = True} b.bounds "Let-in not supported in do block. Did you mean (let ... in ...)?"
               <|>
             do atEnd indents
                build (mkDoLets fname res)
      <|> do b <- bounds (keyword KwRewrite *> again.expr pdef fname indents)
             atEnd indents
             st <- node (StRewrite (boundToFC fname b) b.val)
             pure [st]
      <|> do e <- bounds (again.expr plhs fname indents)
             (do atEnd indents
                 st <- node (StExp (virtualiseFC $ boundToFC fname e) e.val)
                 pure [st])
               <|> (do ty <- optional (symbol SymColon *> again.typeExpr (pnoeq pdef) fname indents)
                       b <- bounds $ symbol SymLeftArrow *> [| (again.expr pnowith fname indents, block (patAlt fname)) |]
                       atEnd indents
                       let (v, alts) = b.val
                       let fc = virtualiseFC $ boundToFC fname (mergeBounds e b)
                       st <- node (StBindPat fc e.val ty v alts)
                       pure [st])

    patAlt : OriginDesc -> IndentInfo -> Rule n r (Id FClause)
    patAlt fname indents
        = do symbol SymBar
             caseAlt fname indents

    lazy : OriginDesc -> IndentInfo -> Rule n r (Id FTerm)
    lazy fname indents
        = do tm <- bounds ((exactIdent KLazy)
                           *> again.simpleExpr fname indents
                           <* mustFailBecause "Lazy only takes one argument" (continue indents >> again.simpleExpr fname indents))
             node (TmDelayed (boundToFC fname tm) LLazy tm.val)
      <|> do tm <- bounds ((exactIdent KInf)
                           *> again.simpleExpr fname indents
                           <* mustFailBecause "Inf only takes one argument" (continue indents >> again.simpleExpr fname indents))
             node (TmDelayed (boundToFC fname tm) LInf tm.val)
      <|> do tm <- bounds ((exactIdent KDelay)
                           *> again.simpleExpr fname indents
                           <* mustFailBecause "Delay only takes one argument" (continue indents >> again.simpleExpr fname indents))
             node (TmDelay (boundToFC fname tm) tm.val)
      <|> do tm <- bounds ((exactIdent KForce)
                           *> again.simpleExpr fname indents
                           <* mustFailBecause "Force only takes one argument" (continue indents >> again.simpleExpr fname indents))
             node (TmForce (boundToFC fname tm) tm.val)

    binder : OriginDesc -> IndentInfo -> Rule n r (Id FTerm)
    binder fname indents
        = autoImplicitPi fname indents
      <|> defaultImplicitPi fname indents
      <|> forall_ fname indents
      <|> implicitPi fname indents
      <|> autobindOp pdef fname indents
      <|> explicitPi fname indents
      <|> lam fname indents

    typeExpr : ParseOpts -> OriginDesc -> IndentInfo -> Rule n r (Id FTerm)
    typeExpr q fname indents
        = binder fname indents
      <|> do arg_mscope <- bounds $ do
               arg <- expr q fname indents
               mscope <- optional $ do
                   continue indents
                   bd <- bindSymbol fname
                   scope <- mustWork $ again.typeExpr q fname indents
                   pure (bd, scope)
               pure (arg, mscope)
             mkPi (boundToFC fname arg_mscope) arg_mscope.val

      where
        mkPi : FC -> (Id FTerm, Maybe (PiInfo (Id FTerm), Id FTerm)) -> EmptyRule n True (Id FTerm)
        mkPi _ (arg, Nothing) = pure arg
        mkPi fc (arg, Just (exp, a))
          = node (TmPi fc top exp Nothing arg a)

    expr : ParseOpts -> OriginDesc -> IndentInfo -> Rule n r (Id FTerm)
    expr q fname indents
         = let_ fname indents
       <|> rewrite_ fname indents
       <|> (bounds (pragma fname KwRunElab) >>= \x
             => the (Rule _ _ (Id FTerm)) (fatalLoc x.bounds runElabRefused))
       <|> opExpr q fname indents

    interpBlock : ParseOpts -> OriginDesc -> IndentInfo -> Rule n r (Id FTerm)
    interpBlock q fname idents = interpBegin *> (mustWork $ again.expr q fname idents <* interpEnd)

    singlelineStr : ParseOpts -> OriginDesc -> IndentInfo -> Rule n r (Id FTerm)
    singlelineStr q fname idents
        =
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

    multilineStr : ParseOpts -> OriginDesc -> IndentInfo -> Rule n r (Id FTerm)
    multilineStr q fname idents
        =
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

    fnDirectOpt : OriginDesc -> Rule n r (Id FOpt)
    fnDirectOpt fname
        = do pragma fname KwHint
             node (OpFn (Hint True))
      <|> do pragma fname KwGlobalHint
             node (OpFn (GlobalHint False))
      <|> do pragma fname KwDefaultHint
             node (OpFn (GlobalHint True))
      <|> do pragma fname KwInline
             commit
             node (OpFn Inline)
      <|> do pragma fname KwUnsafe
             commit
             node (OpFn Unsafe)
      <|> do pragma fname KwNoInline
             commit
             node (OpFn NoInline)
      <|> do pragma fname KwDeprecate
             commit
             node (OpFn Deprecate)
      <|> do pragma fname KwTCInline
             commit
             node (OpFn TCInline)
      <|> do pragma fname KwExtern
             node (OpFn ExternFn)
      -- `%macro` makes a function an elaborator script run where it is
      -- applied, which this compiler does not run.
      <|> (bounds (pragma fname KwMacro) >>= \x
            => the (Rule _ _ (Id FOpt)) (fatalLoc x.bounds
                 "unsupported: the pragma %macro makes a function an elaborator script, run where it is applied, and this compiler runs no elaborator script"))
      <|> do pragma fname KwSpec
             ns <- sepBy (symbol SymComma) name
             node (OpFn (SpecArgs ns))
      <|> do pragma fname KwForeign
             cs <- block (again.expr pdef fname)
             node (OpForeign cs)
      -- `%export`, and `%nomangle`, its old spelling, name a function's
      -- symbol for a foreign language to call; this compiler has no foreign
      -- interface, so the pragma is refused where it is read.
      <|> (bounds (pragma fname KwExport <|> pragma fname KwNoMangle) >>= \x
            => the (Rule _ _ (Id FOpt)) (fatalLoc x.bounds
                 "unsupported: the pragma %export names a function for a foreign language to call, and this compiler has no foreign interface"))

    ||| A binder with only one name and one type
    ||| BNF:
    ||| plainBinder := name ':' typeExpr
    plainBinder : (fname : OriginDesc) => (indents : IndentInfo) => Rule n r (Id FPlain)
    plainBinder = do name <- fcBounds (userName)
                     symbol SymColon
                     ty <- again.typeExpr pdef fname indents
                     node (BnPlain name ty)

    ||| A binder with multiple names and one type
    ||| BNF:
    ||| basicMultiBinder := name (, name)* ':' typeExpr
    basicMultiBinder : (fname : OriginDesc) => (indents : IndentInfo) => Rule n r (Id FNames)
    basicMultiBinder
      = do rig <- multiplicity fname
           names <- sepBy1 (symbol SymComma)
                         $ fcBounds (userName)
           symbol SymColon
           ty <- again.typeExpr pdef fname indents
           node (BnNames rig names ty)

    tyDecls : Rule n r Name -> String -> OriginDesc -> IndentInfo -> Rule n r (Id FTyDecl)
    tyDecls declName predoc fname indents
        = do bs <- bounds $ do
                      docns <- sepBy1 (symbol SymComma)
                                      [| (optDocumentation fname, fcBounds declName) |]
                      b <- bounds $ symbol SymColon
                      mustWorkBecause b.bounds "Expected a type declaration" $ do
                        ty <- the (Rule _ _ (Id FTerm)) (again.typeExpr pdef fname indents)
                        pure (docns, ty)
             atEnd indents
             let (docns, ty) = bs.val
             node (TyClaim (boundToFC fname bs) docns predoc ty)

    withProblem : OriginDesc -> Int -> IndentInfo -> Rule n r (Id FWith)
    withProblem fname col indents
      = do rig <- multiplicity fname
           start <- mustWork $ bounds (symbol SymParen)
           wval <- bracketedExpr fname start indents
           prf <- optional $ do
                    keyword KwProof
                    pure (!(multiplicity fname), !(userName))
           node (WpValue rig wval prf)

    parseRHS : (withArgs : Nat) ->
               OriginDesc -> WithBounds t -> Int ->
               IndentInfo -> (lhs : (Id FTerm, List (FC, Id FTerm))) -> Rule n r (Id FClause)
    parseRHS withArgs fname start col indents lhs
         = do b <- bounds $ do
                     symbol SymEquals
                     mustWork $ do
                       continue indents
                       rhs <- again.typeExpr pdef fname indents
                       ws <- option [] $ whereBlock fname col
                       pure (rhs, ws)
              b' <- bounds peek
              mustWorkBecause b'.bounds "Not the end of a block entry, check indentation" $ atEnd indents
              (rhs, ws) <- pure b.val
              let fc = boundToFC fname (mergeBounds start b)
              l <- withApplied lhs
              node (ClPattern fc l rhs ws)
       <|> do b <- bounds $ do
                     keyword KwWith
                     commit
                     flags <- withFlags fname
                     wps <- sepBy1 (symbol SymBar) (withProblem fname col indents)
                     ws <- mustWork $ nonEmptyBlockAfter col
                                    $ again.clause (S (length wps.tail) + withArgs) (Just lhs) fname
                     pure (flags, wps, forget ws)
              (flags, wps, ws) <- pure b.val
              let fc = boundToFC fname (mergeBounds start b)
              l <- withApplied lhs
              node (ClWith fc l wps flags ws)
       <|> do end <- bounds (keyword KwImpossible)
              atEnd indents
              l <- withApplied lhs
              node (ClImpossible (boundToFC fname (mergeBounds start end)) l)

    clause : (withArgs : Nat) ->
             IMaybe (isSucc withArgs) (Id FTerm, List (FC, Id FTerm)) ->
             OriginDesc -> IndentInfo -> Rule n r (Id FClause)
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
                    Rule n r (Id FTerm, List (FC, Id FTerm))
        -- we aren't in a `with` so there is nothing to skip
        clauseLHS fname indent Nothing
          = (,[]) <$> opExpr plhs fname indents
        -- in a with clause, give a different meaning to a `_` lhs
        clauseLHS fname indent (Just lhs)
          = do e <- opExpr plhs fname indents
               Just fc <- build (implicitAt e)
                 | Nothing => pure (e, [])
               relocated (virtualiseFC fc) lhs

        parseWithArg : Rule n True (FC, Id FTerm)
        parseWithArg
            = do symbol SymBar
                 tm <- bounds (again.expr plhs fname indents)
                 pure (boundToFC fname tm, tm.val)

    simpleCon : OriginDesc -> Id FTerm -> IndentInfo -> Rule n r (Id FTyDecl)
    simpleCon fname ret indents
        = do b <- bounds (do cdoc   <- optDocumentation fname
                             cname  <- fcBounds $ dataConstructorName
                             params <- the (EmptyRule _ _ $ List $ WithFC $ List ArgType)
                                         $ many (fcBounds $ argExpr plhs fname indents)
                             let Just args = traverse conArg (concat (map distribData params))
                                   | Nothing => fatalError "Named arguments not allowed in ADT constructors"
                             conType <- dataConType ret args
                             pure (cdoc, cname, conType))
             atEnd indents
             let (cdoc, cname, conType) = b.val
             node (TyClaim (boundToFC fname b) (singleton ("", cname)) cdoc conType)

    simpleData : OriginDesc -> WithBounds t ->
                 WithBounds Name -> IndentInfo -> Rule n r (Id FData)
    simpleData fname start tyName indents
        = do b <- bounds (do params <- many (bounds $ name)
                             tyend <- bounds (symbol SymEquals)
                             mustWork $ do
                               let tyfc = boundToFC fname (mergeBounds start tyend)
                               tyCon <- node (TmRef (boundToFC fname tyName) tyName.val)
                               args <- build (traverse (\ t => make (TmRef (boundToFC fname t) t.val)) params)
                               -- every constructor's return type, one node
                               conRetTy <- build (foldlM (\f, a => make (TmApp tyfc f a)) tyCon args)
                               cons <- sepBy1 (symbol SymBar) (simpleCon fname conRetTy indents)
                               pure (params, tyfc, forget cons))
             (params, tyfc, cons) <- pure b.val
             tyConTy <- tyConType fname tyfc params
             node (DtBody (boundToFC fname (mergeBounds start b)) tyName.val (Just tyConTy) [] cons)

    dataBody : OriginDesc -> Int -> WithBounds t -> Name -> IndentInfo -> Maybe (Id FTerm) ->
              EmptyRule n r (Id FData)
    dataBody fname mincol start tyname indents ty
        = do ty <- maybe (fail "Telescope is not optional in forward declaration") pure ty
             atEndIndent indents
             node (DtLater (boundToFC fname start) tyname ty)
      <|> do b <- bounds (do (mustWork $ keyword KwWhere)
                             opts <- dataOpts fname
                             cs <- blockAfter mincol (tyDecls (mustWork $ dataConstructorName) "" fname)
                             pure (opts, cs))
             (opts, cs) <- pure b.val
             node (DtBody (boundToFC fname (mergeBounds start b)) tyname ty opts cs)

    gadtData : OriginDesc -> Int -> WithBounds t ->
               WithBounds Name -> IndentInfo -> EmptyRule n r (Id FData)
    gadtData fname mincol start tyName indents
        = do ty <- optional $
                     do symbol SymColon
                        commit
                        again.typeExpr pdef fname indents
             dataBody fname mincol start tyName.val indents ty

    dataDeclBody : OriginDesc -> IndentInfo -> Rule n r (Id FData)
    dataDeclBody fname indents
        = do b <- bounds (do col <- column
                             keyword KwData
                             nm <- mustWork (bounds $ dataTypeName)
                             pure (col, nm))
             (col, nm) <- pure b.val
             simpleData fname b nm indents <|> gadtData fname col b nm indents

    dataDecl : (fname : OriginDesc) => (indents : IndentInfo) => Rule n r (DeclOf Id)
    dataDecl
        = do doc         <- optDocumentation fname
             (vis,mbTot) <- dataVisOpt fname
             dat         <- dataDeclBody fname indents
             pure (DcData doc vis mbTot dat)

    directive : (fname : OriginDesc) => (indents : IndentInfo) => Rule n r Directive
    directive
        = do pragma fname KwHide
             n <- (fixityNS <|> (HideName <$> name))
             atEnd indents
             pure (Hide n)
      <|> do pragma fname KwUnhide
             n <- name
             atEnd indents
             pure (Unhide n)
    --   <|> do pragma "hide_export"
    --          n <- name
    --          atEnd indents
    --          pure (Hide True n)
      <|> do pragma fname KwLogging
             lvl <- logLevel fname
             atEnd indents
             pure (Logging lvl)
      <|> do pragma fname KwAutoLazy
             b <- onoff
             atEnd indents
             pure (LazyOn b)
      <|> do pragma fname KwUnboundImplicits
             b <- onoff
             atEnd indents
             pure (UnboundImplicits b)
      <|> do pragma fname KwPrefixRecordProjections
             b <- onoff
             atEnd indents
             pure (PrefixRecordProjections b)
      <|> do pragma fname KwNfMetavarThreshold
             dpt <-  intLit
             atEnd indents
             pure (NFMetavarThreshold (fromInteger dpt))
      <|> do pragma fname KwPair
             ty <- name
             f <- name
             s <- name
             atEnd indents
             pure (PairNames ty f s)
      <|> do pragma fname KwRewrite
             eq <- name
             rw <- name
             atEnd indents
             pure (RewriteName eq rw)
      <|> do pragma fname KwIntegerLit
             n <- name
             atEnd indents
             pure (PrimInteger n)
      <|> do pragma fname KwStringLit
             n <- name
             atEnd indents
             pure (PrimString n)
      <|> do pragma fname KwCharLit
             n <- name
             atEnd indents
             pure (PrimChar n)
      <|> do pragma fname KwDoubleLit
             n <- name
             atEnd indents
             pure (PrimDouble n)
      <|> do pragma fname KwTTImpLit
             n <- name
             atEnd indents
             pure (PrimTTImp n)
      <|> do pragma fname KwNameLit
             n <- name
             atEnd indents
             pure (PrimName n)
      <|> do pragma fname KwDeclsLit
             n <- name
             atEnd indents
             pure (PrimDecls n)
      <|> do pragma fname KwName
             n <- name
             ns <- sepBy1 (symbol SymComma)
                          (userName)
             atEnd indents
             pure (Names n (forget (map nameRoot ns)))
      -- `%start` names the expression a REPL session runs first; this
      -- compiler runs no REPL, so the pragma is refused where it is read.
      <|> (bounds (pragma fname KwStart) >>= \x
            => the (Rule _ _ Directive) (fatalLoc x.bounds
                 "unsupported: the pragma %start names an expression for a REPL session to run, and this compiler runs no REPL"))
      <|> do pragma fname KwAllowOverloads
             n <- name
             atEnd indents
             pure (Overloadable n)
      <|> do pragma fname KwLanguage
             e <- mustWork extension
             atEnd indents
             pure (Extension e)
      <|> do pragma fname KwDefault
             tot <- totalityOpt fname
             atEnd indents
             pure (DefaultTotality tot)

    namespaceDecl : (fname : OriginDesc) => (indents : IndentInfo) => Rule n r (DeclOf Id)
    namespaceDecl
        = do doc <- optDocumentation fname -- documentation is not recoded???
             col <- column
             ns  <- namespaceHead fname
             ds  <- blockAfter col (again.topDecl fname)
             pure (DcNamespace ns ds)

    transformDecl : (fname : OriginDesc) => (indents : IndentInfo) => Rule n r (DeclOf Id)
    transformDecl
        = do pragma fname KwTransform
             n <- simpleStr
             lhs <- again.expr plhs fname indents
             symbol SymEquals
             rhs <- again.expr pnowith fname indents
             pure (DcTransform n lhs rhs)

    runElabDecl : (fname : OriginDesc) => Rule n r (DeclOf Id)
    runElabDecl
        = bounds (pragma fname KwRunElab) >>= \x
            => the (Rule _ _ (DeclOf Id)) (fatalLoc x.bounds runElabRefused)

    ||| failDecls := 'failing' simpleStr? nonEmptyBlock
    failDecls : (fname : OriginDesc) => (indents : IndentInfo) => Rule n r (DeclOf Id)
    failDecls
        = do
             col <- column
             keyword KwFailing
             commit
             msg <- optional ((simpleMultiStr <|> simpleStr ))
             ds <- nonEmptyBlockAfter col (again.topDecl fname)
             pure $ DcFail msg (forget ds)

    ||| mutualDecls := 'mutual' nonEmptyBlock
    mutualDecls : (fname : OriginDesc) => (indents : IndentInfo) => Rule n r (DeclOf Id)
    mutualDecls
        = do
             col <- column
             keyword KwMutual
             commit
             ds <- nonEmptyBlockAfter col (again.topDecl fname)
             pure (DcMutual (forget ds))

    usingDecls : (fname : OriginDesc) => (indents : IndentInfo) => Rule n r (DeclOf Id)
    usingDecls
        = do col <- column
             keyword KwUsing
             commit
             symbol SymParen
             us <- sepBy (symbol SymComma)
                         (do n <- optional $ userName <* symbol SymColon
                             ty <- again.typeExpr pdef fname indents
                             pure (n, ty))
             symbol SymParenClose
             ds <- nonEmptyBlockAfter col (again.topDecl fname)
             pure (DcUsing us (forget ds))


    visOpt : OriginDesc -> Rule n r (Either Visibility (Id FOpt))
    visOpt fname
        = do vis <- visOption fname
             pure (Left vis)
      <|> do tot <- fnOpt fname
             pure (Right tot)
      <|> do opt <- fnDirectOpt fname
             pure (Right opt)

    defImplicitField : OriginDesc -> IndentInfo -> Rule n r (PiInfo (Id FTerm))
    defImplicitField fname indents = do
      keyword KwDefault
      commit
      t <- again.simpleExpr fname indents
      pure (DefImplicit t)

    -- An interface's or an implementation's constraints, each followed by a
    -- `=>`, as many as are written.
    constraints : OriginDesc -> IndentInfo -> EmptyRule n r (List (Maybe Name, Id FTerm))
    constraints fname indents = many constraint
      where
        constraint : Rule n r (Maybe Name, Id FTerm)
        constraint
            = do tm <- appExpr pdef fname indents
                 symbol SymFatArrow
                 pure (Nothing, tm)
          <|> do symbol SymParen
                 n <- name
                 symbol SymColon
                 tm <- again.typeExpr pdef fname indents
                 symbol SymParenClose
                 symbol SymFatArrow
                 pure (Just n, tm)

    -- An implementation's implicit parameters, one for each name bound, each
    -- where its name is, from as many braces as are written.
    implBinds : OriginDesc -> IndentInfo -> (namedImpl : Bool) ->
                EmptyRule n r (List (Id FImplicit))
    implBinds fname indents namedImpl = concat <$> many binds where

      isDefaultImplicit : PiInfo a -> Bool
      isDefaultImplicit (DefImplicit _) = True
      isDefaultImplicit _               = False

      binds : Rule n r (List (Id FImplicit))
      binds = do symbol SymBrace
                 piInfo <- bounds $ option Implicit $ defImplicitField fname indents
                 when (not namedImpl && isDefaultImplicit piInfo.val) $
                   fatalLoc piInfo.bounds "Default implicits are allowed only for named implementations"
                 (rig, names, type) <- pibindListName fname indents
                 ns <- build (traverse (\nm => make (BnImplicit (virtualiseFC nm.fc) rig nm piInfo.val type))
                                       (forget names))
                 commitSymbol fname SymBraceClose
                 commitSymbol fname SymArrow
                 pure ns

    fieldDecl : (fname : OriginDesc) => IndentInfo -> Rule n r (Id FField)
    fieldDecl indents
          = do doc <- optDocumentation fname
               symbol SymBrace
               commit
               impl <- option Implicit (autoImplicitField fname indents <|> defImplicitField fname indents)
               fs <- fieldBody doc impl
               symbol SymBraceClose
               atEnd indents
               pure fs
        <|> do doc <- optDocumentation fname
               fs <- fieldBody doc Explicit
               atEnd indents
               pure fs
      where
        -- A field's names and type, read after a brace or where the field
        -- begins.
        fieldBody : {0 rd : Bool} -> String -> PiInfo (Id FTerm) -> Rule n rd (Id FField)
        fieldBody doc p
            = do b <- bounds $ do
                        rig <- multiplicity fname
                        ns <- sepBy1 (symbol SymComma)
                                (fcBounds (name
                                   <|> (do b <- bounds (symbol SymUnderscore)
                                           fatalLoc {c = True} b.bounds "Fields have to be named")))
                        symbol SymColon
                        ty <- again.typeExpr pdef fname indents
                        pure (rig, forget ns, ty)
                 let (rig, ns, ty) = b.val
                 node (FdField (boundToFC fname b) doc rig ns p ty)

    ifaceParam : (fname : OriginDesc) => (indents : IndentInfo) => Rule n r (Id FNames)
    ifaceParam
        = parens basicMultiBinder
      <|> do n <- fcBounds (name)
             ty <- node (TmInfer n.fc)
             node (BnNames erased (singleton n) ty)

    ifaceDecl : (fname : OriginDesc) => (indents : IndentInfo) => Rule n r (DeclOf Id)
    ifaceDecl
        = do  doc   <- optDocumentation fname
              vis   <- visibility fname
              col   <- column
              keyword KwInterface
              commit
              cons   <- constraints fname indents
              n      <- name
              params <- many ifaceParam
              det    <- optional $ do
                b <- bounds $ symbol SymBar
                mustWorkBecause b.bounds "Expected list of determining parameters" $
                  sepBy1 (symbol SymComma) (name)
              keyword KwWhere
              dc <- optional (recordConstructor fname)
              body <- blockAfter col (again.topDecl fname)
              pure (DcInterface vis cons n doc params det dc body)

    implDecl : (fname : OriginDesc) => (indents : IndentInfo) => Rule n r (DeclOf Id)
    implDecl
        = do doc     <- optDocumentation fname
             visOpts <- many (visOpt fname)
             vis     <- getVisibility Nothing visOpts
             let opts = mapMaybe getRight visOpts
             col <- column
             option () (keyword KwImplementation)
             iname  <- optional $ symbol SymBracket
                               *> name
                               <* symbol SymBracketClose
             impls  <- implBinds fname indents (isJust iname)
             cons   <- constraints fname indents
             n      <- name
             params <- many (continue indents *> again.simpleExpr fname indents)
             nusing <- option [] $ keyword KwUsing
                                *> forget <$> some (name)
             body <- optional $ keyword KwWhere *> blockAfter col (again.topDecl fname)
             atEnd indents
             pure $
                DcImplementation vis opts Single impls cons n params iname nusing body

    localClaim : (fname : OriginDesc) => (indents : IndentInfo) => Rule n r (DeclOf Id)
    localClaim
        = do doc     <- optDocumentation fname
             visOpts <- many (visOpt fname)
             vis     <- getVisibility Nothing visOpts
             let opts = mapMaybe getRight visOpts
             rig  <- multiplicity fname
             cls  <- tyDecls (name)
                             doc fname indents
             pure $ DcClaim rig vis opts cls


    -- A Single binder with multiple names
    typedArg : (fname : OriginDesc) => (indents : IndentInfo) => Rule n r (Id FBinder)
    typedArg
        = do params <- parens $ pibindListName fname indents
             ns <- multiBinder params
             node (BnPi Explicit ns)
      <|> do symbol SymBrace
             commit
             info <-
                      (pure  AutoImplicit <* keyword KwAuto
                  <|> (keyword KwDefault *> DefImplicit <$> again.simpleExpr fname indents)
                  <|> pure      Implicit)
             params <- pibindListName fname indents
             symbol SymBraceClose
             ns <- multiBinder params
             node (BnPi info ns)

    ||| Record parameter, can be either a typed binder or a name
    ||| BNF:
    ||| recordParam := typedArg | name
    recordParam : (fname : OriginDesc) => (indents : IndentInfo) => Rule n r (Id FBinder)
    recordParam
        = typedArg
      <|> do n <- fcBounds (userName)
             ty <- node (TmInfer n.fc)
             ns <- node (BnNames top (singleton n) ty)
             node (BnPi Explicit ns)

    -- A record without a where is a forward declaration
    recordBody : (fname : OriginDesc) => (indents : IndentInfo) =>
                 String -> WithDefault Visibility Private ->
                 Maybe TotalReq ->
                 Int ->
                 Name ->
                 List (Id FBinder) ->
                 EmptyRule n r (DeclOf Id)
    recordBody doc vis mbtot col nm params
        = do atEndIndent indents
             rc <- node (RcLater nm params)
             pure (DcRecord doc vis mbtot rc)
      <|> do mustWork $ keyword KwWhere
             opts <- dataOpts fname
             dcflds <- blockWithOptHeaderAfter col
                         (\ idt => recordConstructor fname <* atEnd idt)
                         fieldDecl
             rc <- node (RcBody nm params opts (fst dcflds) (snd dcflds))
             pure (DcRecord doc vis mbtot rc)

    recordDecl : (fname : OriginDesc) => (indents : IndentInfo) => Rule n r (DeclOf Id)
    recordDecl
        = do doc         <- optDocumentation fname
             (vis,mbtot) <- dataVisOpt fname
             col         <- column
             keyword KwRecord
             nm      <- mustWork (dataTypeName)
             paramss <- many (continue indents >> recordParam)
             recordBody doc vis mbtot col nm paramss

    ||| Parameter blocks
    ||| BNF:
    ||| paramDecls := 'parameters' (oldParamDecls | newParamDecls) indentBlockDefs
    paramDecls : (fname : OriginDesc) => (indents : IndentInfo) => Rule n r (DeclOf Id)
    paramDecls = do
             startCol <- column
             b1 <- keyword KwParameters
             commit
             args <- Right <$> newParamDecls
                 <|> Left <$> withWarning "DEPRECATED: old parameter syntax https://github.com/idris-lang/Idris2/issues/3447" oldParamDecls
             commit
             declarations <- nonEmptyBlockAfter startCol (again.topDecl fname)
             pure (DcParameters args (forget declarations))

      where
        oldParamDecls : Rule n True (List1 (Id FPlain))
        oldParamDecls
            = parens $ sepBy1 (symbol SymComma) plainBinder

        newParamDecls : Rule n True (List1 (Id FBinder))
        newParamDecls = some typedArg


    definition : (fname : OriginDesc) => (indents : IndentInfo) => Rule n r (DeclOf Id)
    definition
        = do nd <- clause 0 Nothing fname indents
             pure (DcDef (singleton nd))


    topDecl : OriginDesc -> IndentInfo -> Rule n r (Id FDecl)
    topDecl fname indents
          -- Specifically check if the user has attempted to use a reserved identifier to begin their declaration to give improved error messages.
          -- i.e. the claim "String : Type" is a parse error, but the underlying reason may not be clear to new users.
        = do id <- anyReservedIdent
             the (Rule _ _ (Id FDecl)) $ fatalLoc id.bounds "Cannot begin a declaration with a reserved identifier"
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
             the (Rule _ _ (Id FDecl)) $ fatalLoc kw.bounds "Imports must go before any declarations or directives"
          -- If the user tried to begin a declaration with any other keyword, then show a more informative error.
      <|> do kw <- bounds anyKeyword
             the (Rule _ _ (Id FDecl)) $ fatalLoc kw.bounds "Keyword '\{keywordText kw.val}' is not a valid start to a declaration"
      <|> fatalError "Couldn't parse declaration"

-- The language's grammars at every bound, each at a bound made of the box
-- of them all at the bounds below it.
grammars : {0 n : Nat} -> Grammars False n
grammars
    = fixpoint {p = Grammars False}
        (\box => let again = reentered box in
                     MkGrammars (expr again) (typeExpr again) (opExpr again) (opExprBase again)
                                (simpleExpr again) (simplerExpr again) (nestedDpair again)
                                (clause again) (topDecl again))

||| A module, its declarations read off its parse tree.
export
prog : OriginDesc -> EmptyRule n False (Read Module)
prog fname
    = do mod <- moduleHead fname
         ds <- block (grammars.topDecl fname)
         pure (\t => (\parsed => { decls := parsed } mod) <$> declsIn ds t)
