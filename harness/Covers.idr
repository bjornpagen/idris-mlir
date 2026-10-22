-- SPDX-License-Identifier: 0BSD
-- Copyright (c) 2026 Bjorn Pagen
||| The prelude's coverage. A program test marked `covers MODULE` is a
||| program that uses every definition MODULE of the stock prelude exports
||| at run time. Which definitions those are is the pinned Idris's: :browse
||| lists them from its checked context, so the list follows the pin and is
||| never written down here. Which the program uses is this compiler's: the
||| module its frontend hands the driver, the one output it writes, names
||| every definition it resolved (moduleNames): a function by its symbol,
||| its key printed (Prelude.Types.List.length[Int]), and by its location,
||| which names the definition it is; a saturated method by its instance,
||| suffixed (Prelude.Num.fromInteger_Num_Int); a definition the registry
||| lowers to an op by that op's location, as a function's names it; and a
||| constructor by a type refined to it, after its family, whose label is
||| its type's key printed (Prelude.Basics.List[Int] refined to ::). And the
||| program's output is held to its cases' expected-stdout as every
||| program's is, so what it uses is also what it computes right. A
||| module's exports are the definitions it makes itself: one it
||| re-exports is covered in the module that defines it.
|||
||| A type, and a definition whose result is a type or an equality (a
||| proof), has no run time: it is named apart, as compile-time only, and
||| not asked of the program. So is an interface's constructor (MkEq),
||| which the pinned Idris names in the interface's :doc: this compiler
||| resolves every implementation at compile time, specialising each method
||| call to the implementation it is given, so the record is never built
||| (an implementation chosen at run time is refused), and the methods' uses
||| are what the program's module shows. Two more kinds are named apart
||| when the module does not name them. An escape hatch, which user code may
||| not write, is asked of the compiler. A decided exclusion is outside the
||| language (threads, collector finalizers). A pointer is a handle of the
||| runtime's, so the prelude's pointer operations are not among them: a
||| program uses them as it uses any other export. Three of them the
||| registry translates to a value, a pointer cast to the handle it is given
||| and the null pointer to the null handle, which leaves no call for the
||| module to name: each is used when the program's own code calls it. So
||| is an implementation, a hint whose body is %search among them, which
||| the pinned Idris's :di names by its compile-time tree. The decided
||| exclusions and those three are the only names written down here, and a
||| later export is still asked of the compiler.
module Covers

import Data.List
import Data.List1
import Data.Maybe
import Data.SortedMap
import Data.SortedSet
import Data.String
import System.File

import Facts
import Files
import Harness
import Lex
import Reject
import Serve

%default covering

------------------------------------------------------------------------------
-- Text
------------------------------------------------------------------------------

dropText : Nat -> String -> String
dropText n = pack . drop n . unpack

takeText : Nat -> String -> String
takeText n = pack . take n . unpack

||| The text before and after the first occurrence of a separator.
splitFirst : (separator : String) -> String -> Maybe (String, String)
splitFirst sep text = go [<] (unpack text)
  where
    go : SnocList Char -> List Char -> Maybe (String, String)
    go _ [] = Nothing
    go before cs@(c :: rest) =
      if isPrefixOf (unpack sep) cs then Just (pack (before <>> []), pack (drop (length sep) cs))
      else go (before :< c) rest

||| Every occurrence of a text replaced by another, left to right.
replaceAll : (old, new : String) -> String -> String
replaceAll old new text = go [<] (unpack text)
  where
    go : SnocList Char -> List Char -> String
    go done [] = pack (done <>> [])
    go done cs@(c :: rest) =
      if old /= "" && isPrefixOf (unpack old) cs
         then go (done <>< unpack new) (drop (length old) cs)
         else go (done :< c) rest

||| A full name's last component and its namespace: an operator's is its
||| parenthesised name (`Prelude.Basics.(.)`), anything else's the text
||| after its last dot.
nameParts : String -> (String, String)
nameParts full =
  let cs = unpack full in
  if isSuffixOf ")" full
     then case splitFirst ".(" full of
            Just (space, op) => ("(" ++ op, space)
            Nothing => (full, "")
     else case break (== '.') (reverse cs) of
            (lastPart, '.' :: space) => (pack (reverse lastPart), pack (reverse space))
            (lastPart, _) => (pack (reverse lastPart), "")

lastPart : String -> String
lastPart = fst . nameParts

spaceOf : String -> String
spaceOf = snd . nameParts

||| The full names, each without the module's prefix, on one line.
shortNames : (module' : String) -> List String -> String
shortNames m = unwords . map (\n => if isPrefixOf (m ++ ".") n then dropText (length m + 1) n else n)

------------------------------------------------------------------------------
-- The pinned Idris, asked
------------------------------------------------------------------------------

||| The pinned prelude's source, from which the pinned Idris built the
||| prelude it loads: its IDE mode names a definition's module by the file
||| it finds for it here.
preludeSource : Env -> String
preludeSource e = e.tools.root ++ "/third_party/Idris2/libs/prelude"

||| The pinned Idris on the lines on its standard input, run in the work
||| directory with OPTIONS: what it printed.
asked : Env -> (options : List String) -> (input : List String) -> ErrorOutput -> IO String
asked e options input err = do
  let dir = sessionDir e.session
  ignore (writeFile (dir ++ "/idris.in") (unlines input))
  _ <- pinnedIdris e options (FromFile (dir ++ "/idris.in")) (ToFile (dir ++ "/idris.out")) err
  fromMaybe "" <$> readIfThere (dir ++ "/idris.out")

||| The pinned Idris's REPL on the commands, then `:q`.
repl : Env -> List String -> ErrorOutput -> IO String
repl e commands = asked e ["--no-banner", "--no-color"] (commands ++ [":q"])

||| A line of the REPL without its prompts.
unprompted : String -> String
unprompted l = if isPrefixOf "Main> " l then unprompted (dropText 6 l) else l

||| An export as :browse lists it: its name (an operator with its
||| parentheses, but one that begins with a dot), its type, and its type
||| with its implicits as Idris prints it with showimplicits, which a
||| program can write, when the two listings line up.
record Export where
  constructor MkExport
  name : String
  type : String
  withImplicits : Maybe String

||| The lines of a :browse, each `name : type`, the name a single word.
browsed : String -> List (String, String)
browsed out = mapMaybe line (lines out)
  where
    line : String -> Maybe (String, String)
    line l = do
      (name, type) <- splitFirst " : " (unprompted l)
      if any (== ' ') (unpack name) then Nothing else Just (name, type)

||| What MODULE exports, in :browse's order.
preludeExports : Env -> (module' : String) -> IO (List Export)
preludeExports e m = do
  let err = Apart (ToFile (inWork e "browse.err"))
  plain <- browsed <$> repl e [":browse " ++ m] err
  shown <- browsed <$> repl e [":set showimplicits", ":browse " ++ m] err
  pure $ if length plain == length shown
    then zipWith (\(n, t), (_, i) => MkExport n t (Just i)) plain shown
    else map (\(n, t) => MkExport n t Nothing) plain

||| Where a definition was made: the module of the prelude's source that
||| holds it, or none that the answer names.
data Home = In String | Unplaced

Eq Home where
  In a == In b = a == b
  Unplaced == Unplaced = True
  _ == _ = False

homeText : Home -> String
homeText (In m) = m
homeText Unplaced = "?"

||| A definition the pinned Idris has: its full name, and where it was made.
record Definition where
  constructor MkDefinition
  full : String
  home : Home

||| A quoted string's body after its opening quote, escapes as written,
||| and what follows its closing quote.
quoted : List Char -> Maybe (List Char, List Char)
quoted [] = Nothing
quoted ('\\' :: c :: rest) = map (\(b, a) => ('\\' :: c :: b, a)) (quoted rest)
quoted ('"' :: rest) = Just ([], rest)
quoted (c :: rest) = map (\(b, a) => (c :: b, a)) (quoted rest)

stripChars : List Char -> List Char -> Maybe (List Char)
stripChars [] cs = Just cs
stripChars (p :: ps) (c :: cs) = if p == c then stripChars ps cs else Nothing
stripChars _ [] = Nothing

||| The definitions an IDE-mode answer of name-at lists, each
||| `("<full name>" (:filename "<file>")`, in order.
answered : List Char -> List (String, String)
answered [] = []
answered cs@(_ :: rest) = case item cs of
  Just (full, file, after) => (full, file) :: answered after
  Nothing => answered rest
  where
    item : List Char -> Maybe (String, String, List Char)
    item ('(' :: '"' :: more) = do
      (full, cs1) <- quoted more
      cs2 <- stripChars (unpack " (:filename \"") cs1
      (file, cs3) <- quoted cs2
      cs4 <- stripChars [')'] cs3
      pure (pack full, pack file, cs4)
    item _ = Nothing

||| The module a file of the prelude's source is.
moduleOfFile : (source, file : String) -> Home
moduleOfFile source file =
  let lead = source ++ "/" in
  if isPrefixOf lead file && isSuffixOf ".idr" file
     then In (pack (map (\c => if c == '/' then '.' else c)
                        (take (minus (length file) (length lead + 4)) (drop (length lead) (unpack file)))))
     else Unplaced

||| Whether an IDE-mode line is a name-at answer: hexadecimal digits, then
||| `(:return (:ok (`.
isAnswer : String -> Bool
isAnswer l = case span (\c => isDigit c || (c >= 'a' && c <= 'f')) (unpack l) of
  (_ :: _, rest) => isPrefixOf (unpack "(:return (:ok (") rest
  _ => False

||| Every definition the pinned Idris has under one of the bare NAMES (as
||| :browse prints them), with its full name and its module. :browse prints
||| a name without its namespace, so a name it lists twice (List.length and
||| String.length) is two definitions; IDE mode's name-at lists every
||| definition of a bare name with its full name and its location, which
||| the checked context keeps as the module that defined it, and which IDE
||| mode prints as that module's file in the pinned source. Only an
||| operator that begins with a dot, (.) or (.:), is out of name-at's reach,
||| which reads `.` as a projection: :di prints its full name, and its
||| module is the one that defines the rest of its namespace.
preludeDefinitions : Env -> List String -> IO (List Definition)
preludeDefinitions e names = do
  let numbered = zip [1 .. length names] names
  let requests = mapMaybe request numbered
  out <- asked e ["--ide-mode", "--source-dir", preludeSource e] requests (Apart (ToFile (inWork e "name-at.err")))
  let namedAt = map (\(full, file) => MkDefinition (unescape full) (moduleOfFile (preludeSource e) file))
                    (concatMap (answered . unpack) (filter isAnswer (lines out)))
  let dotted = filter (isPrefixOf "(.") names
  more <- case dotted of
    [] => pure []
    _ => do
      di <- repl e (map (":di " ++) dotted) (Apart (ToFile "/dev/null"))
      pure (concatMap (dottedDefinition (homes namedAt) dotted) (lines di))
  pure (namedAt ++ more)
  where
    request : (Nat, String) -> Maybe String
    request (n, name) =
      if isPrefixOf "(." name then Nothing else
        let bare = if isPrefixOf "(" name && isSuffixOf ")" name && length name >= 2
                      then takeText (minus (length name) 2) (dropText 1 name) else name
            escaped = replaceAll "\"" "\\\"" (replaceAll "\\" "\\\\" bare)
        in Just ("((:name-at \"" ++ escaped ++ "\") " ++ show n ++ ")")

    unescape : String -> String
    unescape = replaceAll "\\\\" "\\" . replaceAll "\\\"" "\""

    -- The module each namespace's definitions were made in, or none where
    -- they were made in two.
    homes : List Definition -> SortedMap String Home
    homes = foldl (\m, d => let s = spaceOf d.full in
                            case lookup s m of
                              Nothing => insert s d.home m
                              Just h => if h == d.home then m else insert s Unplaced m) empty

    dottedDefinition : SortedMap String Home -> List String -> String -> List Definition
    dottedDefinition of' dotted l0 =
      let l1 = if isPrefixOf "Main> " l0 then dropText 6 l0 else l0
          l = if isPrefixOf "0 " l1 || isPrefixOf "1 " l1 then dropText 2 l1 else l1
      in if any (== ' ') (unpack l) then [] else
           map (\_ => MkDefinition l (fromMaybe Unplaced (lookup (spaceOf l) of')))
               (filter (\n => length l > length n + 1 && isSuffixOf ("." ++ n) l) dotted)

||| An export paired with its definition: one of MODULE's exports with the
||| definition :browse lists it for; an export no definition pairs with; or
||| a definition left over, which :browse does not list.
data Paired = Both Definition Export | ExportAlone Export | DefinitionAlone Definition

pairedLine : Paired -> String
pairedLine (Both d x) = d.full ++ "\t" ++ homeText d.home ++ "\t" ++ x.type ++ "\t" ++ fromMaybe "" x.withImplicits
pairedLine (ExportAlone x) = "?\t?\t" ++ x.type ++ "\t" ++ fromMaybe "" x.withImplicits
pairedLine (DefinitionAlone d) = d.full ++ "\t?\t?\t?"

||| The exports with each one's definition, in :browse's order. :browse
||| lists the visible definitions whose namespace is MODULE's or within it,
||| sorted by full name as Idris orders names: the name, then its
||| namespace innermost component first. So the copies of a name pair off
||| with its definitions in that order.
ownExports : (module' : String) -> List Export -> List Definition -> List Paired
ownExports m exports definitions =
  let candidates = sortBy (\a, b => compare (fst a) (fst b)) (mapMaybe candidate definitions)
      byName = foldl (\acc, ((n, _, _, _), d) => insert n (fromMaybe [] (lookup n acc) ++ [d]) acc) empty candidates
      (paired, left) = pairAll byName exports
  in paired ++ map DefinitionAlone (concat (values left))
  where
    candidate : Definition -> Maybe ((String, String, String, String), Definition)
    candidate d =
      let (name, space) = nameParts d.full in
      if space == m || isPrefixOf (m ++ ".") space
         then Just ((name, concatMap (++ singleton (chr 1)) (reverse (forget (split (== '.') space))), d.full, homeText d.home), d)
         else Nothing

    pairAll : SortedMap String (List Definition) -> List Export -> (List Paired, SortedMap String (List Definition))
    pairAll left [] = ([], left)
    pairAll left (x :: xs) =
      let key = if isPrefixOf "." x.name then "(" ++ x.name ++ ")" else x.name in
      case lookup key left of
        Just (d :: ds) =>
          let (rest, left') = pairAll (insert key ds left) xs in (Both d x :: rest, left')
        _ => let (rest, left') = pairAll left xs in (ExportAlone x :: rest, left')

------------------------------------------------------------------------------
-- What the program's module names
------------------------------------------------------------------------------

||| What a string of the module is: a symbol's name (after `@`), a family's
||| label, a location's name (after `loc(`), or any other.
data Kind = SymbolString | LabelString | LocationString | OtherString

||| Whether a refinement is waiting: none, after a family, or inside its
||| index terms' brackets, how many of them open.
data Waiting = NotWaiting | AfterFamily | InIndices Nat

||| The tokenizer's state over the module's text: whether it is inside a
||| string, the text and kind of that string, the depth of angle brackets
||| with whether each is a family's and its label, whether a label is
||| expected next, whether a refinement is waiting, the family's label it
||| waits after, the labels of the family aliases defined so far, and the
||| names seen, in order.
record Scan where
  constructor MkScan
  inString : Bool
  text : SnocList Char
  kind : Kind
  depth : Nat
  families : SortedMap Nat Bool
  labels : SortedMap Nat String
  expecting : Bool
  waiting : Waiting
  label : String
  aliases : SortedMap String String
  seen : SortedSet String
  names : SnocList String

startScan : Scan
startScan = MkScan False [<] OtherString 0 empty empty False NotWaiting "" empty empty [<]

emit : String -> Scan -> Scan
emit s st = if contains s st.seen then st else { seen $= insert s, names $= (:< s) } st

||| A name read as a symbol: the refinement it is when a family waits for
||| one.
symbol : String -> Scan -> Scan
symbol s st =
  let st' = emit s st in
  case st'.waiting of
    AfterFamily => { waiting := NotWaiting } (emit (st'.label ++ "::" ++ s) st')
    _ => { waiting := NotWaiting } st'

unescaped : List Char -> String
unescaped [] = ""
unescaped ('\\' :: c :: rest) = singleton c ++ unescaped rest
unescaped (c :: rest) = singleton c ++ unescaped rest

symbolChar : Char -> Bool
symbolChar c = isAlphaNum c || c == '_' || c == '$' || c == '.'

aliasChar : Char -> Bool
aliasChar c = isAlphaNum c || c == '_' || c == '$' || c == '.' || c == '-'

||| One line of the module, read as the printer writes it, so no name of
||| it is guessed: a string, a family's angle brackets and an arrow are
||| told apart as tokens. `defining` is the alias the line defines, until
||| its label is read.
scanLine : Scan -> String -> Scan
scanLine st0 line = go defining0 [<] (unpack line) st0
  where
    defining0 : Maybe String
    defining0 =
      case unpack line of
        ('#' :: rest) => case span aliasChar rest of
          (alias@(_ :: _), more) => if isPrefixOf (unpack " = #idr.family<") more then Just (pack alias) else Nothing
          _ => Nothing
        _ => Nothing

    endsWith : SnocList Char -> List Char -> Bool
    endsWith before suffix = from before (reverse suffix)
      where
        from : SnocList Char -> List Char -> Bool
        from _ [] = True
        from (sx :< x) (y :: ys) = x == y && from sx ys
        from [<] (_ :: _) = False

    go : Maybe String -> SnocList Char -> List Char -> Scan -> Scan
    go _ _ [] st = st
    go defining before (c :: rest) st =
      if st.inString then
        case c of
          '\\' => case rest of
            (d :: more) => go defining (before :< c :< d) more ({ text $= (\t => t :< c :< d) } st)
            [] => go defining (before :< c) [] ({ text $= (:< c) } st)
          '"' =>
            let s = unescaped (st.text <>> [])
                st' = { inString := False } st
                after = head' rest
            in case st.kind of
                 SymbolString => go defining (before :< c) rest (symbol s st')
                 LabelString =>
                   let st'' = { labels $= insert st.depth s } st' in
                   case defining of
                     Just alias => go Nothing (before :< c) rest ({ aliases $= insert alias s } st'')
                     Nothing => go Nothing (before :< c) rest st''
                 LocationString => go defining (before :< c) rest ({ waiting := NotWaiting } (emit s st'))
                 OtherString =>
                   go defining (before :< c) rest
                      ({ waiting := NotWaiting } (if after == Just '(' then emit s st' else st'))
          _ => go defining (before :< c) rest ({ text $= (:< c) } st)
      else case st.waiting of
        InIndices brackets =>
          case c of
            '[' => go defining (before :< c) rest ({ waiting := InIndices (S brackets) } st)
            ']' => go defining (before :< c) rest
                     ({ waiting := (case brackets of
                                      S Z => AfterFamily
                                      S k => InIndices k
                                      Z => AfterFamily) } st)
            _ => go defining (before :< c) rest st
        _ =>
          if c == '"' then
            let kind = if endsWith before ['@'] then SymbolString
                       else if st.expecting then LabelString
                       else if endsWith before (unpack "loc(") then LocationString
                       else OtherString
                st' = { inString := True, text := [<], kind := kind } st
            in go defining (before :< c) rest (case kind of
                                                 LabelString => { expecting := False } st'
                                                 _ => st')
          else if c == '@' then
            case rest of
              (h :: _) =>
                if isAlpha h || h == '_'
                   then let (name, more) = span symbolChar rest in
                        go defining (before :< c <>< name) more (symbol (pack name) st)
                   else go defining (before :< c) rest st
              [] => go defining (before :< c) rest st
          else if isPrefixOf (unpack "#idr.family<") (c :: rest) then
            go defining (before <>< unpack "#idr.family<") (drop 11 rest)
               ({ depth $= S, families $= insert (S st.depth) True, expecting := True, waiting := NotWaiting } st)
          else if c == '#' then
            case span aliasChar rest of
              ([], _) => go defining (before :< c) rest ({ waiting := NotWaiting } st)
              (name, more) =>
                let st' = { waiting := NotWaiting } st in
                case lookup (pack name) st.aliases of
                  Just l => if isPrefixOf [' ', '='] more
                               then go defining (before :< c <>< name) more st'
                               else go defining (before :< c <>< name) more ({ label := l, waiting := AfterFamily } st')
                  Nothing => go defining (before :< c <>< name) more st'
          else if c == '-' && head' rest == Just '>' then
            go defining (before :< c :< '>') (drop 1 rest) ({ waiting := NotWaiting } st)
          else if c == '<' then
            go defining (before :< c) rest ({ depth $= S, families $= insert (S st.depth) False, waiting := NotWaiting } st)
          else if c == '>' then
            let family = st.depth > 0 && fromMaybe False (lookup st.depth st.families)
                st' = if family then { label := fromMaybe "" (lookup st.depth st.labels), waiting := AfterFamily } st
                      else { waiting := NotWaiting } st
            in go defining (before :< c) rest ({ depth := pred st'.depth } st')
          else if c == '[' && isAfterFamily st.waiting then
            go defining (before :< c) rest ({ waiting := InIndices 1 } st)
          else if c /= ' ' && c /= '\t' then
            go defining (before :< c) rest ({ waiting := NotWaiting } st)
          else go defining (before :< c) rest st

    isAfterFamily : Waiting -> Bool
    isAfterFamily AfterFamily = True
    isAfterFamily _ = False

||| Every name the bytecode module PROGRAM holds, read off its text as
||| idris-mlir-opt prints it with its locations: each symbol
||| (@Main.main, @"Prelude.Types.List.length[Int]"), each location's name
||| ("Prelude.Types.List.length"(...)), and each constructor a type is
||| refined to, after its family's label, as `<label>::<constructor>`. A
||| family is printed by the alias its definition names (#List =
||| #idr.family<"Prelude.Basics.List[Int]" ...>) or inline; the refinement
||| follows it, after its index terms if it has any (!idr.data<#List
||| @Nil>, !idr.data<#Vect[n] @"::">). None, when the module cannot be
||| read.
moduleNames : Env -> (program : String) -> IO (Maybe (List String))
moduleNames e program = do
  let printed = inWork e "module-names.mlir"
  status <- bounded e [e.tools.idrisMlirOpt, "--mlir-print-debuginfo", program, "-o", printed]
                    (ToFile "/dev/null") (Apart (ToFile (inWork e "module-names.err")))
  if not (succeeded status) then pure Nothing else do
    text <- fromMaybe "" <$> readIfThere printed
    pure (Just ((foldl scanLine startScan (lines text)).names <>> []))

||| Whether `s` ends in NAMESPACE.Type, after one balanced `[...]` if it has
||| one, and the hash an instance whose print drops part of its identity
||| carries after it (`;` and hexadecimal digits).
typeOfSpace : (space : String) -> String -> Bool
typeOfSpace space s0 =
  let s1 = withoutHash (unpack s0) in
  case withoutIndices s1 of
    Nothing => False
    Just s => case stripChars (unpack (space ++ ".")) s of
      Just rest => typeName rest
      Nothing => False
  where
    isHex : Char -> Bool
    isHex c = isDigit c || (c >= 'a' && c <= 'f')

    withoutHash : List Char -> List Char
    withoutHash cs = case break (== ';') (reverse cs) of
      (hex@(_ :: _), ';' :: before) => if all isHex hex then reverse before else cs
      _ => cs

    -- The text before the `[` that the last `]` closes.
    withoutIndices : List Char -> Maybe (List Char)
    withoutIndices cs = case reverse cs of
      (']' :: rest) => go 1 rest
      _ => Just cs
      where
        go : Nat -> List Char -> Maybe (List Char)
        go _ [] = Nothing
        go depth (']' :: more) = go (S depth) more
        go (S Z) ('[' :: more) = Just (reverse more)
        go (S d) ('[' :: more) = go d more
        go Z ('[' :: more) = Nothing
        go depth (_ :: more) = go depth more

    typeName : List Char -> Bool
    typeName ('(' :: rest) = case break (\c => c == '(' || c == ')') rest of
      (_, [')']) => True
      _ => False
    typeName cs@(_ :: _) = all (\c => isAlphaNum c || c == '_' || c == '\'') cs
    typeName [] = False

||| Whether the module's names name the definition of full name FULL: as
||| FULL whole, or with its key arguments after it in brackets, or `;` and
||| the hash a key printed in part ends with; as a saturated method's
||| instance, FULL with its instance suffixed after an underscore
||| (Prelude.Num.fromInteger_Num_Int), an operator's inside its parentheses
||| (Prelude.Num.(-_Neg_Int)); or as a constructor, NS.Type::name, the type
||| one name or an operator in parentheses with its arguments in brackets
||| after it, NS the constructor's namespace, and an operator without its
||| parentheses (Prelude.Basics.List[Int]:::: is (::)).
moduleUses : (full : String) -> List String -> Bool
moduleUses full names = any uses names
  where
    closed : Bool
    closed = isSuffixOf ")" full

    bare : String
    bare = let n = lastPart full in
           if closed then takeText (minus (length n) 2) (dropText 1 n) else n

    space : String
    space = spaceOf full

    constructor' : String
    constructor' = "::" ++ bare

    keyed : List Char -> Bool
    keyed [] = True
    keyed (c :: _) = c == '[' || c == ';'

    instanceChar : Char -> Bool
    instanceChar c = isAlphaNum c || c == '_' || c == '.' || c == '$'

    suffixed : String -> Bool
    suffixed n =
      if closed then
        case stripChars (unpack (space ++ ".(" ++ bare ++ "_")) (unpack n) of
          Just rest => case span instanceChar rest of
            (_ :: _, ')' :: after) => keyed after
            _ => False
          Nothing => False
      else
        case stripChars (unpack (full ++ "_")) (unpack n) of
          Just rest => case span instanceChar rest of
            (_ :: _, after) => keyed after
            _ => False
          Nothing => False

    uses : String -> Bool
    uses n =
      maybe False keyed (stripChars (unpack full) (unpack n))
      || suffixed n
      || (length n > length constructor' && isSuffixOf constructor' n
          && typeOfSpace space (takeText (minus (length n) (length constructor')) n))

------------------------------------------------------------------------------
-- What the program's code calls
------------------------------------------------------------------------------

||| Whether a definition of TYPE has no run time: its result, after the
||| last arrow outside parentheses, is a type or an equality.
compileTimeOnly : String -> Bool
compileTimeOnly type =
  let flat = flatten (unpack type)
      result = last (splitOn flat)
  in endsInType result || isInfixOf (unpack " = ") result
  where
    -- Each innermost parenthesised group made one character, until none.
    innermost : List Char -> Maybe (List Char)
    innermost [] = Nothing
    innermost ('(' :: rest) = case break (\c => c == '(' || c == ')') rest of
      (_, ')' :: after) => Just ('_' :: after)
      _ => map ('(' ::) (innermost rest)
    innermost (c :: rest) = map (c ::) (innermost rest)

    -- One pass replaces every innermost group, as gsub does.
    pass : List Char -> List Char
    pass [] = []
    pass ('(' :: rest) = case break (\c => c == '(' || c == ')') rest of
      (_, ')' :: after) => '_' :: pass after
      (inside, more) => '(' :: inside ++ pass more
    pass (c :: rest) = c :: pass rest

    flatten : List Char -> List Char
    flatten cs = case innermost cs of
      Nothing => cs
      Just _ => flatten (pass cs)

    splitOn : List Char -> List1 (List Char)
    splitOn cs = go [<] [<] cs
      where
        go : SnocList (List Char) -> SnocList Char -> List Char -> List1 (List Char)
        go done cur [] = case done <>> [] of
          [] => (cur <>> []) ::: []
          (p :: ps) => p ::: (ps ++ [cur <>> []])
        go done cur (' ' :: '-' :: '>' :: ' ' :: rest) = go (done :< (cur <>> [])) [<] rest
        go done cur (c :: rest) = go done (cur :< c) rest

    endsInType : List Char -> Bool
    endsInType cs = case reverse cs of
      ('e' :: 'p' :: 'y' :: 'T' :: before) => case before of
        [] => True
        (c :: _) => not (isAlphaNum c || c == '_')
      _ => False

||| Whether the program's own code, its Idris files with comments and
||| strings left out (Lex.idr), names the definition of full name FULL,
||| bare or qualified by any tail of its namespace (Bool.Semigroup.Any for
||| Prelude.Interfaces.Bool.Semigroup.Any). For a registry value that is a
||| call: one applied to less than all its arguments would be the
||| definition itself, whose body the program cannot run.
sourceCalls : (full, fixture : String) -> IO Bool
sourceCalls full fixture = do
  files <- sources fixture
  found <- for files $ \f => do
    text <- fromMaybe "" <$> readIfThere f
    pure (any names (lexed CodeLines text))
  pure (any id found)
  where
    bare : String
    bare = case break (== '.') (reverse (unpack full)) of
      (b, _) => pack (reverse b)

    qualifiers : List String
    qualifiers = case break (== '.') (reverse (unpack full)) of
      (_, '.' :: rest) => tails' (forget (split (== '.') (pack (reverse rest))))
      _ => []
      where
        tails' : List String -> List String
        tails' [] = []
        tails' parts@(_ :: more) = (joinBy "." parts ++ ".") :: tails' more

    outside : Char -> Bool
    outside c = not (isAlphaNum c || c == '_' || c == '\'' || c == '.')

    after : Char -> Bool
    after c = not (isAlphaNum c || c == '_' || c == '\'')

    -- The text before an occurrence of the bare name starts a name there.
    starts : List Char -> Bool
    starts before = case reverse before of
      [] => True
      (c :: _) => outside c

    qualified : List Char -> Bool
    qualified before = any (\q => isSuffixOf (unpack q) before && starts (take (minus (length before) (length q)) before)) qualifiers

    names : String -> Bool
    names line = go [<] (unpack line)
      where
        go : SnocList Char -> List Char -> Bool
        go _ [] = False
        go before cs@(c :: rest) =
          if isPrefixOf (unpack bare) cs && maybe True after (head' (drop (length bare) cs))
             && (let b = before <>> [] in starts b || qualified b)
             then True
             else go (before :< c) rest

    sources : String -> IO (List String)
    sources dir = do
      entries <- namesIn' dir
      map concat $ for entries $ \n => do
        let path = dir ++ "/" ++ n
        if !(isDirectory path) then (if n == "build" then pure [] else sources path)
          else pure (if isSuffixOf ".idr" n then [path] else [])
      where
        namesIn' : String -> IO (List String)
        namesIn' = namesIn

||| Whether FULL is outside the language, by the decision on threads and
||| collector finalizers: the only names written down in this check. A name
||| that is not one of these is asked of the program and, if its module
||| does not name it, of the compiler.
decidedExclusion : String -> Bool
decidedExclusion full = elem full
  [ "Prelude.IO.fork", "Prelude.IO.prim__fork", "Prelude.IO.threadWait", "Prelude.IO.prim__threadWait"
  , "Prelude.IO.onCollect", "Prelude.IO.onCollectAny" ]

||| Whether the registry translates a call of FULL to a value, which leaves
||| no call for the module to name: a pointer cast is the identity on the
||| handle it is given (prim__castPtr, prim__forgetPtr), and so are replace
||| and rewrite__impl on the value they transport, applied to it or not;
||| the null pointer is the null handle, a literal (prim__getNullAnyPtr).
||| The registry's hooks are the compiler's Idris source, which this check
||| cannot ask, so these names are written down, as the decided exclusions
||| are; an export the registry gives another hook is still asked of the
||| module.
registryValue : String -> Bool
registryValue full = elem full
  ["PrimIO.prim__castPtr", "PrimIO.prim__forgetPtr", "PrimIO.prim__getNullAnyPtr", "Builtin.replace", "Builtin.rewrite__impl"]

||| The constructors of the interfaces among the full names, as their :doc
||| names them (in the interface's namespace), all asked of one session of
||| the pinned Idris.
interfaceConstructors : Env -> List String -> IO (List String)
interfaceConstructors e [] = pure []
interfaceConstructors e names = do
  out <- repl e (map (":doc " ++) names) (Apart (ToFile "/dev/null"))
  pure (go 0 False (lines out))
  where
    spaceAt : Nat -> String
    spaceAt i = case drop (minus i 1) names of
      (n :: _) => spaceOf n
      [] => ""

    go : Nat -> Bool -> List String -> List String
    go _ _ [] = []
    go i inside (l :: ls) =
      if isPrefixOf "Main> " l then go (S i) (isPrefixOf "Main> interface " l) ls
      else if inside && isPrefixOf "  Constructor: " l then (spaceAt i ++ "." ++ dropText 15 l) :: go i inside ls
      else go i inside ls

||| The full names that are implementations, all asked of one session of
||| the pinned Idris: :di prints a definition's compile-time tree, and an
||| implementation's is one interface record, built by its constructor
||| (MkSemigroup (...)) or named where it was defined (Num implementation
||| at ...), a hint whose body is %search among them. This compiler
||| resolves every implementation at compile time and never builds the
||| record, so the module names only the saturated calls it typed, each by
||| its own instance: an implementation is used when the program's own
||| code names it, as a registry value is.
implementations : Env -> List String -> IO (List String)
implementations e [] = pure []
implementations e names = do
  out <- repl e (map (":di " ++) names) (Apart (ToFile "/dev/null"))
  pure (go 0 (lines out))
  where
    nameAt : Nat -> String
    nameAt i = case drop (minus i 1) names of
      (n :: _) => n
      [] => ""

    tree : String -> Bool
    tree rest = case unpack rest of
      ('M' :: 'k' :: c :: more) =>
        isUpper c && (case dropWhile (\x => isAlphaNum x || x == '_' || x == '.') more of
                        [] => True
                        (x :: _) => x == ' ' || x == '(')
        || isInfixOf " implementation at " rest
      _ => isInfixOf " implementation at " rest

    go : Nat -> List String -> List String
    go _ [] = []
    go i (l :: ls) =
      if isPrefixOf "Main> " l then go (S i) ls
      else if isPrefixOf "Compile time tree: " l && tree (dropText 19 l) then nameAt i :: go i ls
      else go i ls

||| Whether the compiler under test refuses NAME of MODULE, of TYPE as the
||| pinned Idris prints it with its implicits, in user code as an escape
||| hatch or as a use of the world. The compiler is the one record of what
||| user code may not write (Idris's %unsafe flag, the spellings and the
||| world operations its registry forbids, the primitives of believe_me and
||| idris_crash), so it is asked: a program whose main only names NAME
||| (partial, as NAME may be) is refused. Who refuses is read off the
||| compilation's report (Reject.idr), never its wording: refused, and every
||| error by the rule `escape hatch`, which a use of the world is refused by
||| too, at a line of the probe, whose only code names NAME. `%foreign`, and
||| `%extern` as a C export, are outside the language: not an escape hatch,
||| and not a primitive left to implement. A probe that finds no such
||| refusal leaves its report and output as evidence, which a missing
||| export's line shows.
escapeHatch : Env -> (module', full, type : String) -> (probe : Nat) -> IO (Bool, List String)
escapeHatch e m full type probe = do
  let dir = inWork e ("probe-" ++ show probe)
  made e dir
  ignore (writeFile (dir ++ "/Main.idr") (unlines
    [ "module Main", "", "import Prelude", "import " ++ m, "", "partial", "main : IO ()"
    , "main = let 0 probe : (" ++ type ++ ") = " ++ full ++ " in pure ()" ]))
  _ <- bounded e [e.tools.compileSh, "--report=" ++ dir ++ "/report", dir ++ "/Main.idr", "probe"]
               (ToFile (dir ++ "/out")) WithOutput
  refused <- case ruleNamed "escape hatch" of
    Just rule => refusedAs rule (InFile "Main.idr") (dir ++ "/report")
    Nothing => pure False
  if refused then pure (True, []) else do
    shown <- firstLines 40 [dir ++ "/report", dir ++ "/out"]
    pure (False, (full ++ ": no escape-hatch refusal; the probe's report and output:") :: indented shown)

------------------------------------------------------------------------------
-- The check
------------------------------------------------------------------------------

||| What became of an export of the module the program does not use by
||| name: outside the language, used as a value its code calls, an escape
||| hatch, or missing (with the probe's evidence, when one was asked).
data Unused = Decided | Called | Hatch | Missing (List String)

||| `covers MODULE`: every run-time export of MODULE is used by the program
||| whose module, as its frontend wrote it, is the bytecode PROGRAM, and
||| whose source is FIXTURE's.
export
coversPrelude : Env -> (module', program, fixture : String) -> IO ()
coversPrelude e m program fixture = do
  names <- if program == "" then pure Nothing else moduleNames e program
  case names of
    Nothing => do
      tell e ("prelude " ++ m ++ ": the program's module cannot be read")
      showIn e [inWork e "module-names.err"]
    Just used => do
      exports <- preludeExports e m
      definitions <- preludeDefinitions e (sort (nub (map (.name) exports)))
      let paired = ownExports m exports definitions
      if any unpaired paired
         then do
           tell e ("prelude " ++ m ++ ": the pinned Idris's exports and definitions do not pair off")
           tellAll e (indented (take 20 [show n ++ ":" ++ l | (n, l) <- zip [1 .. length paired] (map pairedLine paired), isInfixOf "?" l]))
         else do
           let own = [(d.full, x) | Both d x <- paired, d.home == In m]
           let others = length [() | Both d _ <- paired, d.home /= In m]
           case own of
             [] => nothingOwn others
             _ => judge used own
  where
    unpaired : Paired -> Bool
    unpaired (Both d _) = d.home == Unplaced
    unpaired _ = True

    -- :browse prints the same nothing for a module that exports nothing
    -- (Prelude.Ops declares only fixities) and for one that does not
    -- exist, so the pinned Idris is asked to import it: a module it imports
    -- and that lists no export of its own has nothing a program could use.
    -- Its --check exits 0 on an error too, so an error is told by what it
    -- prints.
    nothingOwn : Nat -> IO ()
    nothingOwn others = do
      ignore (writeFile (inWork e "Imports.idr") ("module Imports\nimport " ++ m ++ "\n"))
      _ <- pinnedIdris e ["--no-banner", "--no-color", "--check", "Imports.idr"] NoInput (ToFile (inWork e "import.out")) WithOutput
      out <- fromMaybe "" <$> readIfThere (inWork e "import.out")
      if any (isPrefixOf "Error:") (lines out)
         then do
           tell e ("prelude " ++ m ++ ": the pinned Idris neither lists an export nor imports the module")
           showIn e [inWork e "import.out", inWork e "browse.err"]
         else if others == 0
           then tell e ("prelude " ++ m ++ ": exports nothing at run time")
           else tell e ("prelude " ++ m ++ ": exports nothing of its own; its " ++ show others
                        ++ " exports are other modules', each left to the module that defines it")

    -- The names of a kind set apart, after a count: `one` names a single
    -- one, `many` several, each with what it is.
    apart : (one, many : String) -> List String -> String
    apart one many names = case length names of
      Z => ""
      S Z => "; 1 " ++ one ++ ": " ++ shortNames m names
      n => "; " ++ show n ++ " " ++ many ++ ": " ++ shortNames m names

    judge : List String -> List (String, Export) -> IO ()
    judge used own = do
      constructors <- interfaceConstructors e [full | (full, x) <- own, isSuffixOf "Type" x.type]
      let compileTime = [full | (full, x) <- own, compileTimeOnly x.type || elem full constructors]
      let byName = [(full, x) | (full, x) <- own, not (compileTimeOnly x.type || elem full constructors), moduleUses full used]
      let unused = [(full, x) | (full, x) <- own, not (compileTimeOnly x.type || elem full constructors), not (moduleUses full used)]
      impls <- implementations e (map fst unused)
      fates <- for (zip [1 .. length unused] unused) $ \(probe, (full, x)) =>
        if decidedExclusion full then pure (full, Decided)
        else do
          called <- if registryValue full || elem full impls then sourceCalls full fixture else pure False
          if called then pure (full, Called) else
            case x.withImplicits of
              Just type => do
                (hatch, evidence) <- escapeHatch e m full type probe
                pure (full, if hatch then Hatch else Missing evidence)
              Nothing => pure (full, Missing [])
      let hatches = [f | (f, Hatch) <- fates]
      let decided = [f | (f, Decided) <- fates]
      let missing = [f | (f, Missing _) <- fates]
      let evidence = concat [ev | (_, Missing ev) <- fates]
      let usedCount = length byName + length [() | (_, Called) <- fates]
      let exported = length own
      let note = " (" ++ show (length compileTime) ++ " compile-time only: " ++ shortNames m compileTime
                 ++ apart "escape hatch, which user code may not write"
                          "escape hatches, which user code may not write" hatches
                 ++ apart "decided exclusion, which is outside the language this compiler implements"
                          "decided exclusions, which are outside the language this compiler implements" decided
      case missing of
        [] => tell e ("prelude " ++ m ++ ": " ++ show exported ++ " exports, each used" ++ note ++ ")")
        _ => do
          tell e ("prelude " ++ m ++ ": " ++ show exported ++ " exports; " ++ show usedCount ++ " used, these not: "
                  ++ shortNames m missing ++ note ++ ")")
          tellAll e evidence
