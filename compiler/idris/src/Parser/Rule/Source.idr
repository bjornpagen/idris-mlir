-- SPDX-License-Identifier: BSD-3-Clause
-- Copyright (c) 2020 Edwin Brady
module Parser.Rule.Source

import public Parser.Lexer.Source
import public Parser.Support

import Core.Metadata
import Data.List1
import Data.SnocList
import Data.String
import Idris.Syntax
import Libraries.Text.Bounded

%hide Core.Core.(>>)
%hide Core.Core.(>>=)

%default total

||| This version of the Parser's state is parameterized over
||| the container for SemanticDecorations. The parser should
||| only work the ParsingState type below and after parsing
||| is complete, use the regular State type.
public export
record ParserState (container : Type -> Type) where
  constructor MkState
  decorations : container ASemanticDecoration
  holeNames : List Ident
  ||| The pragmas the source writes, each where it is written: a branch
  ||| that fails takes its state with it, so only what the parse kept is here.
  pragmaUses : container PragmaUse

||| This state needs to provide efficient concatenation.
public export
ParsingState : Type
ParsingState = ParserState SnocList

||| This is the final state after parsing. We no longer
||| need to support efficient concatenation.
public export
State : Type
State = ParserState List

export
toState : ParsingState -> State
toState (MkState decs hs ps) = MkState (cast decs) hs (cast ps)

-- To help prevent concatenation slow downs, we only
-- provide Semigroup and Monoid for the efficient
-- version of the ParserState.
export
Semigroup ParsingState where
  MkState decs1 hs1 ps1 <+> MkState decs2 hs2 ps2
    = MkState (decs1 <+> decs2) (hs1 ++ hs2) (ps1 <+> ps2)

export
Monoid ParsingState where
  neutral = MkState [<] [] [<]

public export
BRule : Bool -> Type -> Type
BRule = Grammar ParsingState Token

public export
Rule : Type -> Type
Rule = BRule True

public export
EmptyRule : Type -> Type
EmptyRule = BRule False

export
actD : List ASemanticDecoration -> EmptyRule ()
actD s = act (MkState (cast s) [] [<])

export
actH : Ident -> EmptyRule ()
actH s = act (MkState [<] [s] [<])

||| A magic debug directive, with where it is written.
export
debugInfo : Rule (DebugInfo, Bounds)
debugInfo = terminalAt "Expected a magic debug info directive" $ \case
  MagicDebugInfo di => Just di
  _ => Nothing

export
eoi : EmptyRule ()
eoi = ignore $ nextIs "Expected end of input" isEOI
  where
    isEOI : Token -> Bool
    isEOI EndInput = True
    isEOI _ = False

export
constant : Rule Constant
constant
    = terminal "Expected constant" $ \case
        CharLit c    => Ch <$> getCharLit c
        DoubleLit d  => Just (Db d)
        IntegerLit i => Just (BI i)
        Ident s      => isConstantType (UN $ Basic s) >>=
                             \case WorldType => Nothing
                                   c         => Just $ PrT c
        _            => Nothing

documentation' : Rule String
documentation' = terminal "Expected documentation comment" $
                          \case
                            DocComment d => Just d
                            _ => Nothing

-- A value parsed from no input decorates nothing.
export
decorationFromBounded : {0 a : Type} -> OriginDesc -> Decoration -> WithBounds a -> List ASemanticDecoration
decorationFromBounded fname decor bnds
   = case bnds.bounds of
          Just bs => [((fname, startBounds bs, endBounds bs), decor, Nothing)]
          Nothing => []

documentation : OriginDesc -> Rule String
documentation fname
  = do b <- bounds (some documentation')
       actD (decorationFromBounded fname Comment b)
       pure (unlines $ forget b.val)

export
optDocumentation : OriginDesc -> EmptyRule String
optDocumentation fname = option "" (documentation fname)

export
intLit : Rule Integer
intLit
    = terminal "Expected integer literal" $
               \case
                 IntegerLit i => Just i
                 _ => Nothing

export
onOffLit : Rule Bool
onOffLit
    = terminal "Expected on or off" $
               \case
                 Ident s => onOff (knownOf s)
                 _ => Nothing
  where
    onOff : Maybe Known -> Maybe Bool
    onOff (Just Kon) = Just True
    onOff (Just Koff) = Just False
    onOff _ = Nothing

export
simpleStrLit : Rule String
simpleStrLit
    = terminal "Expected string literal" $
               \case
                 StringLit s => unescape 0 s
                 _ => Nothing

||| String literal split by line wrap (not striped).
export
strLitLines : Rule (List1 String)
strLitLines
    = terminal "Expected string literal" $
               \case
                 StringLit s => Just $ map pack (linesHelp [] (unpack s))
                 _ => Nothing
  where
  linesHelp : List Char -> List Char -> List1 (List Char)
  linesHelp [] [] = List1.singleton []
  linesHelp acc [] = List1.singleton (reverse acc)
  linesHelp acc ('\n' :: xs) = reverse ('\n' :: acc) `List1.cons` linesHelp [] xs
  linesHelp acc ('\r' :: '\n' :: xs) = reverse ('\n' :: '\r' :: acc) `List1.cons` linesHelp [] xs
  linesHelp acc ('\r' :: xs) = reverse ('\r' :: acc) `List1.cons` linesHelp [] xs
  linesHelp acc (c :: xs) = linesHelp (c :: acc) xs

export
strBegin : Rule Nat
strBegin = terminal "Expected string begin" $
                    \case
                      StringBegin hashtag Single => Just hashtag
                      _ => Nothing

export
multilineBegin : Rule Nat
multilineBegin = terminal "Expected multiline string begin" $
                          \case
                            StringBegin hashtag Multi => Just hashtag
                            _ => Nothing

export
strEnd : Rule ()
strEnd = terminal "Expected string end" $
                  \case
                    StringEnd => Just ()
                    _ => Nothing

export
interpBegin : Rule ()
interpBegin = terminal "Expected string interp begin" $
                       \case
                         InterpBegin => Just ()
                         _ => Nothing

export
interpEnd : Rule ()
interpEnd = terminal "Expected string interp end" $
                     \case
                       InterpEnd => Just ()
                       _ => Nothing

export
simpleStr : Rule String
simpleStr = strBegin *> commit *> (option "" simpleStrLit) <* strEnd

export
simpleMultiStr : Rule String
simpleMultiStr = multilineBegin *> commit *> (option "" simpleStrLit) <* strEnd

export
aDotIdent : Rule Ident
aDotIdent = terminal "Expected dot+identifier" $
                     \case
                       DotIdent s => Just s
                       _ => Nothing

export
postfixProj : Rule Name
postfixProj = UN . Field <$> aDotIdent

||| The reserved symbol given.
export
symbol : Reserved -> Rule ()
symbol req
    = terminal ("Expected '" ++ reservedText req ++ "'") $
               \case
                 Reserved r => guard (r == req)
                 _ => Nothing

||| The operator's symbol given, by its identifier.
export
exactSymbol : Known -> Rule ()
exactSymbol req
    = terminal ("Expected '" ++ spelling req ++ "'") $
               \case
                 Symbol s => guard (s == known req)
                 _ => Nothing

export
anyKeyword : Rule Keyword
anyKeyword
  = terminal ("Expected a keyword") $
             \case
               Keyword k => Just k
               _ => Nothing

||| The keyword given.
export
keyword : Keyword -> Rule ()
keyword req
    = terminal ("Expected '" ++ keywordText req ++ "'") $
               \case
                 Keyword k => guard (k == req)
                 _ => Nothing

||| The identifier given, by its id.
export
exactIdent : Known -> Rule ()
exactIdent req
    = terminal ("Expected " ++ spelling req) $
               \case
                 Ident s => guard (s == known req)
                 _ => Nothing

||| The pragma given, its use recorded where it is written.
export
pragma : OriginDesc -> KwPragma -> Rule ()
pragma fname kw
    = do (_, b) <- terminalAt ("Expected pragma " ++ spelling kw) $
                     \case
                       Pragma k => guard (k == kw)
                       _ => Nothing
         act (MkState [<] [] [<MkPragmaUse kw (MkFC fname (startBounds b) (endBounds b))])

export
cgDirective : Rule String
cgDirective =
  terminal "Expected CG directive" $
    \case
      CGDirective d => Just d
      _ => Nothing

export
builtinType : Rule BuiltinType
builtinType =
    BuiltinNatural <$ exactIdent KNatural
    <|> NaturalToInteger <$ exactIdent KNaturalToInteger
    <|> IntegerToNatural <$ exactIdent KIntegerToNatural

-- An operator's name, or the reserved symbol written where one was
-- expected, which names none.
operatorCandidate : Rule (Either Reserved Name)
operatorCandidate
    = terminal "Expected operator" $
               \case
                 Symbol s => Just (Right (UN $ Basic s)) -- TODO: have an operator construct?
                 Reserved r => Just (Left r)
                 _ => Nothing

export
unqualifiedOperatorName : Rule Ident
unqualifiedOperatorName
    = terminal "Expected operator" $
               \case
                 Symbol s => Just s
                 _ => Nothing

export
operator : Rule Name
operator = UN . Basic <$> unqualifiedOperatorName
               -- ^ TODO: add an operator constructor?

identPart : Rule Ident
identPart
    = terminal "Expected name" $
               \case
                 Ident str => Just str
                 _ => Nothing

export
namespacedIdent : Rule (Maybe Namespace, Ident)
namespacedIdent
    = terminal "Expected namespaced name" $
               \case
                 DotSepIdent ns n => Just (Just (nsOf ns), n)
                 Ident i => Just (Nothing, i)
                 _ => Nothing

isCapitalisedIdent : WithBounds Ident -> EmptyRule ()
isCapitalisedIdent str =
  let val = str.val.text
      loc = str.bounds
      err : EmptyRule ()
          = failLoc loc ("Expected a capitalised identifier, got: \{val}")
  in case strUncons val of
       Nothing => err
       Just (c, _) => if (isUpper c || c > chr 160) then pure () else err

export
namespaceId : Rule Namespace
namespaceId = do
  nsid <- bounds namespacedIdent
  isCapitalisedIdent (snd <$> nsid)
  pure (uncurry mkNestedNamespace nsid.val)

||| A bracket, or its namespaced form after a namespace.
export
namespacedSymbol : (plain, dotted : Reserved) -> Rule (Maybe Namespace)
namespacedSymbol plain dotted = do
  (symbol plain $> Nothing) <|> do
    ns <- namespaceId
    symbol dotted
    pure (Just ns)

export
moduleIdent : Rule ModuleIdent
moduleIdent = nsAsModuleIdent <$> namespaceId

export
unqualifiedName : Rule Ident
unqualifiedName = identPart

export
userName : Rule Name
userName = UN . Basic <$> unqualifiedName

export
holeName : Rule Ident
holeName
    = terminal "Expected hole name" $
               \case
                 HoleIdent str => Just str
                 _ => Nothing

-- An identifier no definition may take: `Type`, a primitive type's name,
-- or a laziness primitive's.
reservedName : Ident -> Bool
reservedName i = case knownOf i of
  Just KType => True
  Just KInt => True
  Just KInt8 => True
  Just KInt16 => True
  Just KInt32 => True
  Just KInt64 => True
  Just KInteger => True
  Just KBits8 => True
  Just KBits16 => True
  Just KBits32 => True
  Just KBits64 => True
  Just KString => True
  Just KChar => True
  Just KDouble => True
  Just KLazy => True
  Just KInf => True
  Just KForce => True
  Just KDelay => True
  _ => False

export
anyReservedIdent : Rule (WithBounds Ident)
anyReservedIdent = do
    id <- bounds identPart
    unless (reservedName id.val) $ failLoc id.bounds "Expected reserved identifier"
    pure id

isNotReservedName : WithBounds Ident -> EmptyRule ()
isNotReservedName x
    = when (reservedName x.val) $
        failLoc x.bounds $ "Can't use reserved name \{x.val.text}"

export
opNonNS : Rule Name
opNonNS = do
  symbol SymParen
  commit
  id <- bounds (operatorCandidate <|> Right <$> postfixProj)
  n <- operatorIn id
  symbol SymParenClose
  pure n
  where
    operatorIn : WithBounds (Either Reserved Name) -> EmptyRule Name
    operatorIn x = case x.val of
      Left r => failLoc x.bounds $ "Can't use reserved symbol \{reservedText r}"
      Right n => pure n

identWithCapital : (capitalised : Bool) -> WithBounds Ident ->
                   EmptyRule ()
identWithCapital b x = when b (isCapitalisedIdent x)

nameWithCapital : (capitalised : Bool) -> Rule Name
nameWithCapital b = opNonNS <|> do
  nsx <- bounds namespacedIdent
  opNS nsx <|> nameNS nsx
 where

  nameNS : WithBounds (Maybe Namespace, Ident) -> EmptyRule Name
  nameNS nsx = do
    let id = snd <$> nsx
    identWithCapital b id
    isNotReservedName id
    pure $ uncurry mkNamespacedName (map Basic nsx.val)

  opNS : WithBounds (Maybe Namespace, Ident) -> Rule Name
  opNS nsx = do
    isCapitalisedIdent (snd <$> nsx)
    let ns = uncurry mkNestedNamespace nsx.val
    symbol SymDotParen
    n <- (operator <|> postfixProj)
    symbol SymParenClose
    pure (NS ns n)

export
fixityNS : Rule HidingDirective
fixityNS = do
  namespacePrefix <- bounds namespacedIdent
  let nsVal = namespacePrefix.val
  fx <- checkFixity (knownOf (snd nsVal)) namespacePrefix.bounds
  symbol SymDotParen
  n <- unqualifiedOperatorName
  symbol SymParenClose
  pure (HideFixity fx (NS (uncurry mkNestedNamespace nsVal) $ UN $ Basic n))
  where
    checkFixity : Maybe Known -> Maybe Bounds -> EmptyRule Fixity
    checkFixity (Just Kinfixl) _ = pure InfixL
    checkFixity (Just Kinfixr) _ = pure InfixR
    checkFixity (Just Kinfix)  _ = pure Infix
    checkFixity (Just Kprefix) _ = pure Prefix
    checkFixity _ loc =  failLoc loc ""

export
name : Rule Name
name = nameWithCapital False

export
capitalisedName : Rule Name
capitalisedName = nameWithCapital True

export
capitalisedIdent : Rule Ident
capitalisedIdent = do
  id <- bounds identPart
  isCapitalisedIdent id
  isNotReservedName id
  pure id.val

export
dataConstructorName : Rule Name
dataConstructorName = opNonNS <|> (UN . Basic) <$> capitalisedIdent

export %inline
dataTypeName : Rule Name
dataTypeName = opNonNS <|> capitalisedName

export
IndentInfo : Type
IndentInfo = Int

export
init : IndentInfo
init = 0

continueF : EmptyRule () -> (indent : IndentInfo) -> EmptyRule ()
continueF err indent
    = do eoi; err
  <|> do keyword KwWhere; err
  <|> do col <- column
         when (col <= indent)
            err

||| Fail if this is the end of a block entry or end of file
export
continue : (indent : IndentInfo) -> EmptyRule ()
continue = continueF (fail "Unexpected end of expression")

||| As 'continue' but failing is fatal (i.e. entire parse fails)
export
mustContinue : (indent : IndentInfo) -> Maybe String -> EmptyRule ()
mustContinue indent Nothing
   = continueF (fatalError "Unexpected end of expression") indent
mustContinue indent (Just req)
   = continueF (fatalError ("Expected '" ++ req ++ "'")) indent

data ValidIndent =
  |||  In {}, entries can begin in any column
  AnyIndent |
  ||| Entry must begin in a specific column
  AtPos Int |
  ||| Entry can begin in this column or later
  AfterPos Int |
  ||| Block is finished
  EndOfBlock

Show ValidIndent where
  show AnyIndent = "[any]"
  show (AtPos i) = "[col " ++ show i ++ "]"
  show (AfterPos i) = "[after " ++ show i ++ "]"
  show EndOfBlock = "[EOB]"

checkValid : ValidIndent -> Int -> EmptyRule ()
checkValid AnyIndent c = pure ()
checkValid (AtPos x) c = unless (c == x) $ fail "Invalid indentation"
checkValid (AfterPos x) c = unless (c >= x) $ fail "Invalid indentation"
checkValid EndOfBlock c = fail "End of block"

||| A symbol which ends a statement/block/expression
terminatorSymbol : Reserved -> Bool
terminatorSymbol SymComma = True
terminatorSymbol SymBracketClose = True
terminatorSymbol SymSemicolon = True
terminatorSymbol SymBraceClose = True
terminatorSymbol SymParenClose = True
terminatorSymbol SymBar = True
terminatorSymbol SymStarStar = True
terminatorSymbol _ = False

||| Any token which indicates the end of a statement/block/expression
isTerminator : Token -> Bool
isTerminator (Reserved r) = terminatorSymbol r
isTerminator (Keyword KwIn) = True
isTerminator (Keyword KwThen) = True
isTerminator (Keyword KwElse) = True
isTerminator (Keyword KwWhere) = True
isTerminator InterpEnd = True
isTerminator EndInput = True
isTerminator _ = False

||| Check we're at the end of a block entry, given the start column
||| of the block.
||| It's the end if we have a terminating token, or the next token starts
||| in or before indent. Works by looking ahead but not consuming.
export
atEnd : (indent : IndentInfo) -> EmptyRule ()
atEnd indent
    = eoi
  <|> do ignore $ nextIs "Expected end of block" isTerminator
  <|> do col <- column
         when (not (col <= indent))
            $ fail "Not the end of a block entry"

-- Check we're at the end, but only by looking at indentation
export
atEndIndent : (indent : IndentInfo) -> EmptyRule ()
atEndIndent indent
    = eoi
  <|> do col <- column
         when (not (col <= indent))
            $ fail "Not the end of a block entry"


-- Parse a terminator, return where the next block entry
-- must start, given where the current block entry started
terminator : ValidIndent -> Int -> EmptyRule ValidIndent
terminator valid laststart
    = do eoi
         pure EndOfBlock
  <|> do symbol SymSemicolon
         pure (afterSemi valid)
  <|> do col <- column
         afterDedent valid col
  <|> pure EndOfBlock
 where
   -- Expected indentation for the next token can either be anything (if
   -- we're inside a brace delimited block) or anywhere after the initial
   -- column (if we're inside an indentation delimited block)
   afterSemi : ValidIndent -> ValidIndent
   afterSemi AnyIndent = AnyIndent -- in braces, anything goes
   afterSemi (AtPos c) = AfterPos c -- not in braces, after the last start position
   afterSemi (AfterPos c) = AfterPos c
   afterSemi EndOfBlock = EndOfBlock

   -- Expected indentation for the next token can either be anything (if
   -- we're inside a brace delimited block) or in exactly the initial column
   -- (if we're inside an indentation delimited block)
   afterDedent : ValidIndent -> Int -> EmptyRule ValidIndent
   afterDedent AnyIndent col
       = if col <= laststart
            then pure AnyIndent
            else fail "Not the end of a block entry"
   afterDedent (AfterPos c) col
       = if col <= laststart
            then pure (AtPos c)
            else fail "Not the end of a block entry"
   afterDedent (AtPos c) col
       = if col <= laststart
            then pure (AtPos c)
            else fail "Not the end of a block entry"
   afterDedent EndOfBlock col = pure EndOfBlock

-- Parse an entry in a block
blockEntry : ValidIndent -> (IndentInfo -> Rule ty) ->
             Rule (ty, ValidIndent)
blockEntry valid rule
    = do col <- column
         checkValid valid col
         p <- rule col
         valid' <- terminator valid col
         pure (p, valid')

blockEntries : ValidIndent -> (IndentInfo -> Rule ty) ->
               EmptyRule (List ty)
blockEntries valid rule
     = do eoi; pure []
   <|> do res <- blockEntry valid rule
          -- after an entry, which consumes: on a shorter input
          ts <- assert_total $ blockEntries (snd res) rule
          pure (fst res :: ts)
   <|> pure []

export
block : (IndentInfo -> Rule ty) -> EmptyRule (List ty)
block item
    = do symbol SymBrace
         commit
         ps <- blockEntries AnyIndent item
         symbol SymBraceClose
         pure ps
  <|> do col <- column
         blockEntries (AtPos col) item


||| `blockAfter col rule` parses a `rule`-block indented by at
||| least `col` spaces (unless the block is explicitly delimited
||| by curly braces). `rule` is a function of the actual indentation
||| level.
export
blockAfter : Int -> (IndentInfo -> Rule ty) -> EmptyRule (List ty)
blockAfter mincol item
    = do symbol SymBrace
         commit
         ps <- blockEntries AnyIndent item
         symbol SymBraceClose
         pure ps
  <|> do col <- column
         ifThenElse (col <= mincol)
            (pure [])
            $ blockEntries (AtPos col) item

export
blockWithOptHeaderAfter :
   (column : Int) ->
   (header : IndentInfo -> Rule hd) ->
   (item : IndentInfo -> Rule ty) ->
   EmptyRule (Maybe hd, List ty)
blockWithOptHeaderAfter {ty} mincol header item
    = do symbol SymBrace
         commit
         hidt <- optional $ blockEntry AnyIndent header
         restOfBlock hidt
  <|> do col <- column
         ifThenElse (col <= mincol)
            (pure (Nothing, []))
            $ do hidt <- optional $ blockEntry (AtPos col) header
                 ps <- blockEntries (AtPos col) item
                 pure (map fst hidt, ps)
  where
  restOfBlock : Maybe (hd, ValidIndent) -> Rule (Maybe hd, List ty)
  restOfBlock (Just (h, idt)) = do ps <- blockEntries idt item
                                   symbol SymBraceClose
                                   pure (Just h, ps)
  restOfBlock Nothing = do ps <- blockEntries AnyIndent item
                           symbol SymBraceClose
                           pure (Nothing, ps)

export
nonEmptyBlock : (IndentInfo -> Rule ty) -> Rule (List1 ty)
nonEmptyBlock item
    = do symbol SymBrace
         commit
         res <- blockEntry AnyIndent item
         ps <- blockEntries (snd res) item
         symbol SymBraceClose
         pure (fst res ::: ps)
  <|> do col <- column
         res <- blockEntry (AtPos col) item
         ps <- blockEntries (snd res) item
         pure (fst res ::: ps)

||| `nonEmptyBlockAfter col rule` parses a non-empty `rule`-block indented
||| by at least `col` spaces (unless the block is explicitly delimited
||| by curly braces). `rule` is a function of the actual indentation
||| level.
export
nonEmptyBlockAfter : Int -> (IndentInfo -> Rule ty) -> Rule (List1 ty)
nonEmptyBlockAfter mincol item
    = do symbol SymBrace
         commit
         res <- blockEntry AnyIndent item
         ps <- blockEntries (snd res) item
         symbol SymBraceClose
         pure (fst res ::: ps)
  <|> do col <- column
         let False = col <= mincol
            | True => fatalError "Expected an indented non-empty block"
         res <- blockEntry (AtPos col) item
         ps <- blockEntries (snd res) item
         pure (fst res ::: ps)
