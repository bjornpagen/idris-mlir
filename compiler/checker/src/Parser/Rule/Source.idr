-- SPDX-License-Identifier: BSD-3-Clause
-- Copyright (c) 2020 Edwin Brady
module Parser.Rule.Source

import public Parser.Lexer.Source
import public Parser.Support

import Core.Metadata
import Data.List1
import Data.String
import Idris.Syntax
import Idris.Syntax.Tree
import Libraries.Text.Bounded

%hide Core.Core.(>>)
%hide Core.Core.(>>=)

%default total

||| What parsing a source has made so far: its semantic decorations and the
||| pragmas it writes, each where it is written, and its parse tree's nodes.
||| The parse holds it once, so each is written in place; a branch that
||| fails cuts what it wrote back off, so only what the parse kept is here.
export
data ParsingState : Type where
  MkParsing : (1 decorated : Trail ASemanticDecoration) ->
              (1 pragmasWritten : Trail PragmaUse) ->
              (1 tree : Builder) -> ParsingState

||| Nothing parsed yet.
export
parsing : ParsingState
parsing = MkParsing blank blank noNodes

||| Where a parse's state stands: how far each of its parts is written.
export
record Marks where
  constructor MkMarks
  decorationsAt : Nat
  pragmasAt : Nat
  nodesAt : Nat

-- The state given back, with where each of its parts stands.
standing : (1 decorated : Stepped (Trail ASemanticDecoration) Nat) ->
           (1 pragmasWritten : Stepped (Trail PragmaUse) Nat) ->
           (1 tree : Stepped Builder Nat) -> Stepped ParsingState Marks
standing (MkStepped ds d) (MkStepped ps p) (MkStepped t n) = MkStepped (MkParsing ds ps t) (MkMarks d p n)

||| A state stands where its parts do, and goes back by taking each back.
export
Backtrack Marks ParsingState where
  here (MkParsing ds ps t) = standing (here ds) (here ps) (here t)
  backTo m (MkParsing ds ps t)
      = MkParsing (backTo m.decorationsAt ds) (backTo m.pragmasAt ps) (backTo m.nodesAt t)

||| What a parse made, once it is done: its decorations and the pragmas it
||| writes, each in the order written, and its tree's nodes.
export
madeBy : ParsingState -> (List ASemanticDecoration, List PragmaUse, Builder)
madeBy (MkParsing ds ps t) = (contents ds, contents ps, t)

||| What parsing a source made, once it is done: its decorations, the names
||| of the holes it writes, read from its tree's hole nodes, and the
||| pragmas it writes.
public export
record State where
  constructor MkState
  decorations : List ASemanticDecoration
  holeNames : List Ident
  pragmaUses : List PragmaUse

||| A grammar of a source, at bound `n`, run below it if `r`, consuming if
||| `c`.
public export
BRule : (n : Nat) -> (r : Bool) -> (c : Bool) -> Type -> Type
BRule = Grammar ParsingState Token

||| A grammar of a source that reads a token wherever it succeeds.
public export
Rule : (n : Nat) -> (r : Bool) -> Type -> Type
Rule n r = BRule n r True

||| A grammar of a source that may succeed reading nothing.
public export
EmptyRule : (n : Nat) -> (r : Bool) -> Type -> Type
EmptyRule n r = BRule n r False

-- The entries given, written after those before them, in order.
writeAll : List a -> (1 trail : Trail a) -> Trail a
writeAll [] trail = trail
writeAll (x :: xs) trail = writeAll xs (write x trail)

-- The state with the decorations given written.
decorating : List ASemanticDecoration -> (1 st : ParsingState) -> Stepped ParsingState ()
decorating s (MkParsing ds ps t) = MkStepped (MkParsing (writeAll s ds) ps t) ()

export
actD : List ASemanticDecoration -> EmptyRule n r ()
actD s = updateState (decorating s)

-- The state with its tree as a step of making it gave it back.
withTree : (1 decorated : Trail ASemanticDecoration) -> (1 pragmasWritten : Trail PragmaUse) ->
           (1 step : Stepped Builder a) -> Stepped ParsingState a
withTree ds ps (MkStepped t x) = MkStepped (MkParsing ds ps t) x

-- The state with a step of making its tree taken.
building : Build a -> (1 st : ParsingState) -> Stepped ParsingState a
building b (MkParsing ds ps t) = withTree ds ps (runBuild b t)

||| A step of making the parse tree, taken in the parse's state, so that a
||| branch that fails drops the nodes it made.
export
build : Build a -> EmptyRule n r a
build b = updateState (building b)

||| A node of the parse tree, of the form its rule gives, made of what the
||| rule parsed.
export
node : NodeOf Id -> EmptyRule n r (Id x)
node nd = build (make nd)

||| A magic debug directive, with where it is written.
export
debugInfo : Rule n r (DebugInfo, Bounds)
debugInfo = terminalAt "Expected a magic debug info directive" $ \case
  MagicDebugInfo di => Just di
  _ => Nothing

export
eoi : EmptyRule n r ()
eoi = ignore $ nextIs "Expected end of input" isEOI
  where
    isEOI : Token -> Bool
    isEOI EndInput = True
    isEOI _ = False

export
constant : Rule n r Constant
constant
    = terminal "Expected constant" $ \case
        CharLit c    => Ch <$> getCharLit c
        DoubleLit d  => Just (Db d)
        IntegerLit i => Just (BI i)
        Ident s      => isConstantType (UN $ Basic s) >>=
                             \case WorldType => Nothing
                                   c         => Just $ PrT c
        _            => Nothing

documentation' : Rule n r String
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

documentation : OriginDesc -> Rule n r String
documentation fname
  = do b <- bounds (some documentation')
       actD (decorationFromBounded fname Comment b)
       pure (unlines $ forget b.val)

export
optDocumentation : OriginDesc -> EmptyRule n r String
optDocumentation fname = option "" (documentation fname)

export
intLit : Rule n r Integer
intLit
    = terminal "Expected integer literal" $
               \case
                 IntegerLit i => Just i
                 _ => Nothing

export
onOffLit : Rule n r Bool
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
simpleStrLit : Rule n r String
simpleStrLit
    = terminal "Expected string literal" $
               \case
                 StringLit s => unescape 0 s
                 _ => Nothing

||| String literal split by line wrap (not striped).
export
strLitLines : Rule n r (List1 String)
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
strBegin : Rule n r Nat
strBegin = terminal "Expected string begin" $
                    \case
                      StringBegin hashtag Single => Just hashtag
                      _ => Nothing

export
multilineBegin : Rule n r Nat
multilineBegin = terminal "Expected multiline string begin" $
                          \case
                            StringBegin hashtag Multi => Just hashtag
                            _ => Nothing

export
strEnd : Rule n r ()
strEnd = terminal "Expected string end" $
                  \case
                    StringEnd => Just ()
                    _ => Nothing

export
interpBegin : Rule n r ()
interpBegin = terminal "Expected string interp begin" $
                       \case
                         InterpBegin => Just ()
                         _ => Nothing

export
interpEnd : Rule n r ()
interpEnd = terminal "Expected string interp end" $
                     \case
                       InterpEnd => Just ()
                       _ => Nothing

export
simpleStr : Rule n r String
simpleStr = strBegin *> commit *> (option "" simpleStrLit) <* strEnd

export
simpleMultiStr : Rule n r String
simpleMultiStr = multilineBegin *> commit *> (option "" simpleStrLit) <* strEnd

export
aDotIdent : Rule n r Ident
aDotIdent = terminal "Expected dot+identifier" $
                     \case
                       DotIdent s => Just s
                       _ => Nothing

export
postfixProj : Rule n r Name
postfixProj = UN . Field <$> aDotIdent

||| The reserved symbol given.
export
symbol : Reserved -> Rule n r ()
symbol req
    = terminal ("Expected '" ++ reservedText req ++ "'") $
               \case
                 Reserved r => guard (r == req)
                 _ => Nothing

||| The operator's symbol given, by its identifier.
export
exactSymbol : Known -> Rule n r ()
exactSymbol req
    = terminal ("Expected '" ++ spelling req ++ "'") $
               \case
                 Symbol s => guard (s == known req)
                 _ => Nothing

export
anyKeyword : Rule n r Keyword
anyKeyword
  = terminal ("Expected a keyword") $
             \case
               Keyword k => Just k
               _ => Nothing

||| The keyword given.
export
keyword : Keyword -> Rule n r ()
keyword req
    = terminal ("Expected '" ++ keywordText req ++ "'") $
               \case
                 Keyword k => guard (k == req)
                 _ => Nothing

||| The identifier given, by its id.
export
exactIdent : Known -> Rule n r ()
exactIdent req
    = terminal ("Expected " ++ spelling req) $
               \case
                 Ident s => guard (s == known req)
                 _ => Nothing

-- The state with a pragma's use written.
usingPragma : PragmaUse -> (1 st : ParsingState) -> Stepped ParsingState ()
usingPragma use (MkParsing ds ps t) = MkStepped (MkParsing ds (write use ps) t) ()

||| The pragma given, its use recorded where it is written.
export
pragma : OriginDesc -> KwPragma -> Rule n r ()
pragma fname kw
    = do (_, b) <- terminalAt ("Expected pragma " ++ spelling kw) $
                     \case
                       Pragma k => guard (k == kw)
                       _ => Nothing
         updateState (usingPragma (MkPragmaUse kw (MkFC fname (startBounds b) (endBounds b))))

export
cgDirective : Rule n r String
cgDirective =
  terminal "Expected CG directive" $
    \case
      CGDirective d => Just d
      _ => Nothing

export
builtinType : Rule n r BuiltinType
builtinType =
    BuiltinNatural <$ exactIdent KNatural
    <|> NaturalToInteger <$ exactIdent KNaturalToInteger
    <|> IntegerToNatural <$ exactIdent KIntegerToNatural

-- An operator's name, or the reserved symbol written where one was
-- expected, which names none.
operatorCandidate : Rule n r (Either Reserved Name)
operatorCandidate
    = terminal "Expected operator" $
               \case
                 Symbol s => Just (Right (UN $ Basic s)) -- TODO: have an operator construct?
                 Reserved r => Just (Left r)
                 _ => Nothing

export
unqualifiedOperatorName : Rule n r Ident
unqualifiedOperatorName
    = terminal "Expected operator" $
               \case
                 Symbol s => Just s
                 _ => Nothing

export
operator : Rule n r Name
operator = UN . Basic <$> unqualifiedOperatorName
               -- ^ TODO: add an operator constructor?

identPart : Rule n r Ident
identPart
    = terminal "Expected name" $
               \case
                 Ident str => Just str
                 _ => Nothing

export
namespacedIdent : Rule n r (Maybe Namespace, Ident)
namespacedIdent
    = terminal "Expected namespaced name" $
               \case
                 DotSepIdent ns n => Just (Just (nsOf ns), n)
                 Ident i => Just (Nothing, i)
                 _ => Nothing

isCapitalisedIdent : WithBounds Ident -> EmptyRule n r ()
isCapitalisedIdent str =
  let val = str.val.text
      loc = str.bounds
      err : EmptyRule n r ()
          = failLoc loc ("Expected a capitalised identifier, got: \{val}")
  in case strUncons val of
       Nothing => err
       Just (c, _) => if (isUpper c || c > chr 160) then pure () else err

export
namespaceId : Rule n r Namespace
namespaceId = do
  nsid <- bounds namespacedIdent
  isCapitalisedIdent (snd <$> nsid)
  pure (uncurry mkNestedNamespace nsid.val)

||| A bracket, or its namespaced form after a namespace.
export
namespacedSymbol : (plain, dotted : Reserved) -> Rule n r (Maybe Namespace)
namespacedSymbol plain dotted = do
  (symbol plain $> Nothing) <|> do
    ns <- namespaceId
    symbol dotted
    pure (Just ns)

export
moduleIdent : Rule n r ModuleIdent
moduleIdent = nsAsModuleIdent <$> namespaceId

export
unqualifiedName : Rule n r Ident
unqualifiedName = identPart

export
userName : Rule n r Name
userName = UN . Basic <$> unqualifiedName

export
holeName : Rule n r Ident
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
anyReservedIdent : Rule n r (WithBounds Ident)
anyReservedIdent = do
    id <- bounds identPart
    unless (reservedName id.val) $ failLoc id.bounds "Expected reserved identifier"
    pure id

isNotReservedName : WithBounds Ident -> EmptyRule n r ()
isNotReservedName x
    = when (reservedName x.val) $
        failLoc x.bounds $ "Can't use reserved name \{x.val.text}"

export
opNonNS : Rule n r Name
opNonNS = do
  symbol SymParen
  commit
  id <- bounds (operatorCandidate <|> Right <$> postfixProj)
  n <- operatorIn id
  symbol SymParenClose
  pure n
  where
    operatorIn : WithBounds (Either Reserved Name) -> EmptyRule n True Name
    operatorIn x = case x.val of
      Left r => failLoc x.bounds $ "Can't use reserved symbol \{reservedText r}"
      Right n => pure n

identWithCapital : (capitalised : Bool) -> WithBounds Ident ->
                   EmptyRule n r ()
identWithCapital b x = when b (isCapitalisedIdent x)

nameWithCapital : (capitalised : Bool) -> Rule n r Name
nameWithCapital b = opNonNS <|> do
  nsx <- bounds namespacedIdent
  opNS nsx <|> nameNS nsx
 where

  nameNS : WithBounds (Maybe Namespace, Ident) -> EmptyRule n True Name
  nameNS nsx = do
    let id = snd <$> nsx
    identWithCapital b id
    isNotReservedName id
    pure $ uncurry mkNamespacedName (map Basic nsx.val)

  opNS : WithBounds (Maybe Namespace, Ident) -> Rule n True Name
  opNS nsx = do
    isCapitalisedIdent (snd <$> nsx)
    let ns = uncurry mkNestedNamespace nsx.val
    symbol SymDotParen
    n <- (operator <|> postfixProj)
    symbol SymParenClose
    pure (NS ns n)

export
fixityNS : Rule n r HidingDirective
fixityNS = do
  namespacePrefix <- bounds namespacedIdent
  let nsVal = namespacePrefix.val
  fx <- checkFixity (knownOf (snd nsVal)) namespacePrefix.bounds
  symbol SymDotParen
  n <- unqualifiedOperatorName
  symbol SymParenClose
  pure (HideFixity fx (NS (uncurry mkNestedNamespace nsVal) $ UN $ Basic n))
  where
    checkFixity : Maybe Known -> Maybe Bounds -> EmptyRule n True Fixity
    checkFixity (Just Kinfixl) _ = pure InfixL
    checkFixity (Just Kinfixr) _ = pure InfixR
    checkFixity (Just Kinfix)  _ = pure Infix
    checkFixity (Just Kprefix) _ = pure Prefix
    checkFixity _ loc =  failLoc loc ""

export
name : Rule n r Name
name = nameWithCapital False

export
capitalisedName : Rule n r Name
capitalisedName = nameWithCapital True

export
capitalisedIdent : Rule n r Ident
capitalisedIdent = do
  id <- bounds identPart
  isCapitalisedIdent id
  isNotReservedName id
  pure id.val

export
dataConstructorName : Rule n r Name
dataConstructorName = opNonNS <|> (UN . Basic) <$> capitalisedIdent

export %inline
dataTypeName : Rule n r Name
dataTypeName = opNonNS <|> capitalisedName

export
IndentInfo : Type
IndentInfo = Int

export
init : IndentInfo
init = 0

continueF : EmptyRule n r () -> (indent : IndentInfo) -> EmptyRule n r ()
continueF err indent
    = do eoi; err
  <|> do keyword KwWhere; later err
  <|> do col <- column
         when (col <= indent)
            err

||| Fail if this is the end of a block entry or end of file
export
continue : (indent : IndentInfo) -> EmptyRule n r ()
continue = continueF (fail "Unexpected end of expression")

||| As 'continue' but failing is fatal (i.e. entire parse fails)
export
mustContinue : (indent : IndentInfo) -> Maybe String -> EmptyRule n r ()
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

checkValid : ValidIndent -> Int -> EmptyRule n r ()
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
atEnd : (indent : IndentInfo) -> EmptyRule n r ()
atEnd indent
    = eoi
  <|> do ignore $ nextIs "Expected end of block" isTerminator
  <|> do col <- column
         when (not (col <= indent))
            $ fail "Not the end of a block entry"

-- Check we're at the end, but only by looking at indentation
export
atEndIndent : (indent : IndentInfo) -> EmptyRule n r ()
atEndIndent indent
    = eoi
  <|> do col <- column
         when (not (col <= indent))
            $ fail "Not the end of a block entry"


-- Parse a terminator, return where the next block entry
-- must start, given where the current block entry started
terminator : ValidIndent -> Int -> EmptyRule n r ValidIndent
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
   afterDedent : ValidIndent -> Int -> EmptyRule n r ValidIndent
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
blockEntry : ValidIndent -> (IndentInfo -> Rule n r ty) ->
             Rule n r (ty, ValidIndent)
blockEntry valid rule
    = do col <- column
         checkValid valid col
         p <- rule col
         valid' <- terminator valid col
         pure (p, valid')

-- A block's entries from the first, each entry's indentation given by the
-- one before it, until the end of input or an entry that is not there.
blockEntries : ValidIndent -> (IndentInfo -> Rule n r ty) ->
               EmptyRule n r (List ty)
blockEntries valid rule = entries eoi (\v => blockEntry v rule) valid

||| A block of entries: in braces, its entries after the brace, so below
||| the bound; else from the column the first is at, where the block is.
export
block : (IndentInfo -> Rule n r ty) -> EmptyRule n r (List ty)
block item
    = do symbol SymBrace
         commit
         ps <- blockEntries AnyIndent (later . item)
         symbol SymBraceClose
         pure ps
  <|> do col <- column
         blockEntries (AtPos col) item


||| `blockAfter col rule` parses a `rule`-block indented by at
||| least `col` spaces (unless the block is explicitly delimited
||| by curly braces). `rule` is a function of the actual indentation
||| level.
export
blockAfter : Int -> (IndentInfo -> Rule n r ty) -> EmptyRule n r (List ty)
blockAfter mincol item
    = do symbol SymBrace
         commit
         ps <- blockEntries AnyIndent (later . item)
         symbol SymBraceClose
         pure ps
  <|> do col <- column
         ifThenElse (col <= mincol)
            (pure [])
            $ blockEntries (AtPos col) item

export
blockWithOptHeaderAfter :
   (column : Int) ->
   (header : IndentInfo -> Rule n r hd) ->
   (item : IndentInfo -> Rule n r ty) ->
   EmptyRule n r (Maybe hd, List ty)
blockWithOptHeaderAfter {n} {ty} mincol header item
    = do symbol SymBrace
         commit
         hidt <- optional $ blockEntry AnyIndent (later . header)
         restOfBlock hidt
  <|> do col <- column
         ifThenElse (col <= mincol)
            (pure (Nothing, []))
            $ do hidt <- optional $ blockEntry (AtPos col) header
                 ps <- blockEntries (AtPos col) item
                 pure (map fst hidt, ps)
  where
  -- What follows the brace and the header, if there is one.
  restOfBlock : Maybe (hd, ValidIndent) -> Rule n True (Maybe hd, List ty)
  restOfBlock (Just (h, idt)) = do ps <- blockEntries idt (later . item)
                                   symbol SymBraceClose
                                   pure (Just h, ps)
  restOfBlock Nothing = do ps <- blockEntries AnyIndent (later . item)
                           symbol SymBraceClose
                           pure (Nothing, ps)

export
nonEmptyBlock : (IndentInfo -> Rule n r ty) -> Rule n r (List1 ty)
nonEmptyBlock item
    = do symbol SymBrace
         commit
         res <- blockEntry AnyIndent (later . item)
         ps <- blockEntries (snd res) (later . item)
         symbol SymBraceClose
         pure (fst res ::: ps)
  <|> do col <- column
         res <- blockEntry (AtPos col) item
         ps <- blockEntries (snd res) (later . item)
         pure (fst res ::: ps)

||| `nonEmptyBlockAfter col rule` parses a non-empty `rule`-block indented
||| by at least `col` spaces (unless the block is explicitly delimited
||| by curly braces). `rule` is a function of the actual indentation
||| level.
export
nonEmptyBlockAfter : Int -> (IndentInfo -> Rule n r ty) -> Rule n r (List1 ty)
nonEmptyBlockAfter mincol item
    = do symbol SymBrace
         commit
         res <- blockEntry AnyIndent (later . item)
         ps <- blockEntries (snd res) (later . item)
         symbol SymBraceClose
         pure (fst res ::: ps)
  <|> do col <- column
         let False = col <= mincol
            | True => fatalError "Expected an indented non-empty block"
         res <- blockEntry (AtPos col) item
         ps <- blockEntries (snd res) (later . item)
         pure (fst res ::: ps)
