module Idris.CommandLine

import Idris.Env
import Idris.Version
import Idris.Doc.Display
import Idris.Doc.String
import Idris.Pretty

import Core.Options

import Data.Maybe
import Data.String
import Libraries.Utils.String
import Data.Either

import System

%default total

public export
data PkgCommand
      = Build
      | Install
      | InstallWithSrc
      | Typecheck
      | Clean
      | DumpInstallDir

export
Show PkgCommand where
  show Build = "--build"
  show Install = "--install"
  show InstallWithSrc = "--install-with-src"
  show Typecheck = "--typecheck"
  show Clean = "--clean"
  show DumpInstallDir = "--dump-installdir"

public export
data DirCommand
      = LibDir | -- show top level package directory
         ||| Show the installation prefix
        Prefix |
        BlodwenPaths

export
Show DirCommand where
  show LibDir = "--libdir"
  show Prefix = "--prefix"
  show BlodwenPaths = "--paths"

||| Help topics
public export
data HelpTopic
  = ||| Interactive debugging topics
    HelpLogging
  | ||| The various pragmas
    HelpPragma

recogniseHelpTopic : String -> Maybe HelpTopic
recogniseHelpTopic "logging"   = pure HelpLogging
recogniseHelpTopic "pragma" = pure HelpPragma
recogniseHelpTopic _ = Nothing

||| CLOpt - possible command line options
public export
data CLOpt
  =
   ||| Only typecheck the given file
  CheckOnly |
   ||| The output file from the code generator
  OutputFile String |
   ||| Execute a given function after checking the source file
  ExecFn String |
   ||| Use a specific code generator
  SetCG String |
   ||| Pass a directive to the code generator
  Directive String |
   ||| Don't implicitly import Prelude
  NoPrelude |
   ||| Set source directory
  SourceDir String |
   ||| Set build directory
  BuildDir String |
   ||| Set output directory
  OutputDir String |
   ||| Display Idris version
  Version |
   ||| Display the TTC version currently used
  TTCVersion |
   ||| Display help text
  Help (Maybe HelpTopic) |
   ||| Suppress the banner
  NoBanner |
   ||| Run Idris 2 in quiet mode
  Quiet |
   ||| Show implicits when pretty printing
  ShowImplicits |
   ||| Show machine names when pretty printing
  ShowMachineNames |
   ||| Show namespaces when pretty printing
  ShowNamespaces |
   ||| Run Idris 2 in verbose mode (cancels quiet if it's the default)
  Verbose |
   ||| Set the console width for messages
  ConsoleWidth (Maybe Nat) |
   ||| Whether to use color in the console output
  Color Bool |
   ||| Set the log level globally
  Logging LogLevel |
   ||| Add a package as a dependency
  PkgPath String |
   ||| List installed packages
  ListPackages |
   ||| Build or install a given package, depending on PkgCommand
  Package PkgCommand (Maybe String) |
   ||| Show locations of data/library directories
  Directory DirCommand |
   ||| The input Idris file
  InputFile String |
  IgnoreMissingIPKG |
  FindIPKG |
  Timing (Maybe Nat) |
  DebugElabCheck |
  AltErrorCount Nat |
   ||| Treat warnings as errors
  WarningsAsErrors |
   ||| Do not print shadowing warnings
  IgnoreShadowingWarnings |
   ||| Apply experimental heuristics to case tree generation that
   ||| sometimes improves performance and reduces compiled code
   ||| size.
  CaseTreeHeuristics |
   ||| Turn on %default total globally
  Total

data OptType
  = Required String
   | Optional String
   | RequiredNat String
   | AutoNat String
   | RequiredLogLevel String

Show OptType where
  show (Required a) = "<" ++ a ++ ">"
  show (RequiredNat a) = "<" ++ a ++ ">"
  show (RequiredLogLevel a) = "<" ++ a ++ ">"
  show (Optional a) = "[" ++ a ++ "]"
  show (AutoNat a) = "<" ++ a ++ ">"

-- Each argument is made with its description and its reader at once, the
-- reader reading it as the description says, so that what the help shows
-- is what is read; a value whose type the descriptions computed would be a
-- field whose type depends on another field.
||| The arguments an option's flag takes: how the help text shows them, and
||| how the words after the flag are read as them (given the flag, for its
||| messages), with the words left after them.
record OptArgs a where
  constructor MkArgs
  descs : List OptType
  parse : String -> List String -> Either String (a, List String)

Functor OptArgs where
  map f args = MkArgs args.descs $ \flag, ws =>
    do (x, rest) <- args.parse flag ws
       Right (f x, rest)

||| Arguments in order, each read from the words the one before it left.
Applicative OptArgs where
  pure x = MkArgs [] $ \_, ws => Right (x, ws)
  fs <*> xs = MkArgs (fs.descs ++ xs.descs) $ \flag, ws =>
    do (f, ws') <- fs.parse flag ws
       (x, rest) <- xs.parse flag ws'
       Right (f x, rest)

missing : OptType -> String -> Either String a
missing opt flag = Left $ "Missing required argument " ++ show opt ++ " for flag " ++ flag

checkNat : Integer -> Maybe Nat
checkNat n = toMaybe (n >= 0) (integerToNat n)

required : String -> OptArgs String
required a = MkArgs [Required a] $ \flag, ws => case ws of
  [] => missing (Required a) flag
  x :: xs => Right (x, xs)

||| An optional argument is not given when the next word is a flag, which is
||| left to be read as one.
optional : String -> OptArgs (Maybe String)
optional a = MkArgs [Optional a] $ \flag, ws => case ws of
  [] => Right (Nothing, [])
  x :: xs => if isPrefixOf "-" x
               then Right (Nothing, x :: xs)
               else Right (Just x, xs)

requiredNat : String -> OptArgs Nat
requiredNat a = MkArgs [RequiredNat a] $ \flag, ws => case ws of
  [] => missing (RequiredNat a) flag
  x :: xs =>
    do arg <- maybeToEither ("Expected Nat argument " ++ show x ++ " for flag " ++ flag)
                            (parseSigned x >>= checkNat)
       Right (arg, xs)

requiredLogLevel : String -> OptArgs LogLevel
requiredLogLevel a = MkArgs [RequiredLogLevel a] $ \flag, ws => case ws of
  [] => missing (RequiredLogLevel a) flag
  x :: xs =>
    do arg <- maybeToEither ("Expected LogLevel argument " ++ show x ++ " for flag " ++ flag)
                            (parseLogLevel x)
       Right (arg, xs)

||| A natural number, or `auto` for none.
autoNat : String -> OptArgs (Maybe Nat)
autoNat a = MkArgs [AutoNat a] $ \flag, ws => case ws of
  [] => missing (AutoNat a) flag
  "auto" :: xs => Right (Nothing, xs)
  x :: xs =>
    do arg <- maybeToEither ("Expected Nat or \"auto\" argument " ++ show x ++ " for flag " ++ flag)
                            (parseSigned x >>= checkNat)
       Right (Just arg, xs)

record OptDesc where
  constructor MkOpt
  flags : List String
  action : OptArgs (List CLOpt)
  help : Maybe String

optSeparator : OptDesc
optSeparator = MkOpt [] (pure []) Nothing

showDefault : Show a => a -> String
showDefault x = "(default " ++ show x ++ ")"

options : List OptDesc
options = [MkOpt ["--check", "-c"] (pure [CheckOnly])
              (Just "Exit after checking source file"),
           MkOpt ["--output", "-o"] (required "file" <&> \f => [OutputFile f, Quiet])
              (Just "Specify output file"),
           MkOpt ["--exec", "-x"] (required "name" <&> \f => [ExecFn f, Quiet])
              (Just "Execute expression"),
           MkOpt ["--no-prelude"] (pure [NoPrelude])
              (Just "Don't implicitly import Prelude"),
           MkOpt ["--codegen", "--cg"] (required "backend" <&> \f => [SetCG f])
              (Just "Set code generator"),
           MkOpt ["--directive"] (required "directive" <&> \d => [Directive d])
              (Just $ "Pass a directive to the current code generator"),
           MkOpt ["--package", "-p"] (required "package" <&> \f => [PkgPath f])
              (Just "Add a package as a dependency"),
           MkOpt ["--source-dir"] (required "dir" <&> \d => [SourceDir d])
              (Just $ "Set source directory"),
           MkOpt ["--build-dir"] (required "dir" <&> \d => [BuildDir d])
              (Just $ "Set build directory"),
           MkOpt ["--output-dir"] (required "dir" <&> \d => [OutputDir d])
              (Just $ "Set output directory"),

           optSeparator,
           MkOpt ["--total"] (pure [Total])
              (Just "Require functions to be total by default"),
           MkOpt ["-Werror"] (pure [WarningsAsErrors])
              (Just "Treat warnings as errors"),
           MkOpt ["-Wno-shadowing"] (pure [IgnoreShadowingWarnings])
              (Just "Do not print shadowing warnings"),

           optSeparator,
           MkOpt ["-Xcase-tree-opt"] (pure [CaseTreeHeuristics])
              (Just "Apply experimental optimizations to case tree generation"),

           optSeparator,
           MkOpt ["--prefix"] (pure [Directory Prefix])
              (Just "Show installation prefix"),
           MkOpt ["--paths"] (pure [Directory BlodwenPaths])
              (Just "Show paths"),
           MkOpt ["--libdir"] (pure [Directory LibDir])
              (Just "Show library directory"),
           MkOpt ["--list-packages"] (pure [ListPackages])
              (Just "List installed packages"),

           optSeparator,
           MkOpt ["--dump-installdir"] (optional "package file" <&>
              \ f => [Package DumpInstallDir f])
              (Just "Dump the location where the given package will be installed"),
           MkOpt ["--build"] (optional "package file" <&>
               \f => [Package Build f])
              (Just "Build modules/executable for the given package"),
           MkOpt ["--install"] (optional "package file" <&>
              \f => [Package Install f])
              (Just "Install the given package"),
           MkOpt ["--install-with-src"] (optional "package file" <&>
              \f => [Package InstallWithSrc f])
              (Just "Install the given package"),
           MkOpt ["--typecheck"] (optional "package file" <&>
              \f => [Package Typecheck f])
              (Just "Typechecks the given package without code generation"),
           MkOpt ["--clean"] (optional "package file" <&> \f => [Package Clean f])
              (Just "Clean intermediate files/executables for the given package"),
           MkOpt ["--find-ipkg"] (pure [FindIPKG])
              (Just "Find and use an .ipkg file in a parent directory."),
           MkOpt ["--ignore-missing-ipkg"] (pure [IgnoreMissingIPKG])
              (Just "Fail silently if a dependency is missing."),

           optSeparator,
           MkOpt ["--timing"] (autoNat "level" <&> \ n => [Timing n])
              (Just "Display timing logs"),

           optSeparator,
           MkOpt ["--no-banner"] (pure [NoBanner])
              (Just "Suppress the banner"),
           MkOpt ["--quiet", "-q"] (pure [Quiet])
              (Just "Quiet mode; display fewer messages"),
           MkOpt ["--console-width"] (autoNat "console width" <&> \l => [ConsoleWidth l])
              (Just "Width for console output (0 for unbounded) (auto by default)"),
          MkOpt ["--show-implicits"] (pure [ShowImplicits])
              (Just "Show implicits when pretty printing"),
           MkOpt ["--show-machine-names"] (pure [ShowMachineNames])
              (Just "Show machine names when pretty printing"),
           MkOpt ["--show-namespaces"] (pure [ShowNamespaces])
              (Just "Show namespaces when pretty printing"),
           MkOpt ["--color", "--colour"] (pure [Color True])
              (Just "Forces colored console output (enabled by default)"),
           MkOpt ["--no-color", "--no-colour"] (pure [Color False])
              (Just "Disables colored console output"),
           MkOpt ["--verbose"] (pure [Verbose])
              (Just "Verbose mode (default)"),
           MkOpt ["--log"] (requiredLogLevel "log level" <&> \l => [Logging l])
              (Just "Global log level (0 by default)"),

           optSeparator,
           MkOpt ["--version", "-v"] (pure [Version])
              (Just "Display version string"),
           MkOpt ["--ttc-version"] (pure [TTCVersion])
              (Just "Display TTC version string"),
           MkOpt ["--help", "-h", "-?"] (optional "topic" <&> \ tp => [Help (tp >>= recogniseHelpTopic)])
              (Just "Display help text"),

           -- Internal debugging options
           MkOpt ["--debug-elab-check"] (pure [DebugElabCheck])
              Nothing, -- do more elaborator checks (currently conversion in LinearCheck)
           MkOpt ["--alt-error-count"] (requiredNat "alternative count" <&> \c => [AltErrorCount c])
              (Just "Outputs errors for the given number of alternative parsing attempts.")
           ]

optShow : OptDesc -> (String, Maybe String)
optShow (MkOpt [] _ _) = ("", Just "")
optShow (MkOpt flags action help) = (showSep ", " flags ++ " " ++
                                     showSep " " (map show action.descs),
                                     help)
  where
    showSep : String -> List String -> String
    showSep sep [] = ""
    showSep sep [x] = x
    showSep sep (x :: xs) = x ++ sep ++ showSep sep xs

firstColumnWidth : Nat
firstColumnWidth = let maxOpt = foldr max 0 $ map (length . fst . optShow) options
                       maxEnv = foldr max 0 $ map (length . .name) envs in
                       max maxOpt maxEnv

makeTextFromOptionsOrEnvs : List (String, Maybe String) -> String
makeTextFromOptionsOrEnvs rows = concatMap (optUsage firstColumnWidth) rows
  where
    optUsage : Nat -> (String, Maybe String) -> String
    optUsage maxOpt (optshow, help) = maybe ""  -- Don't show anything if there's no help string (that means
                                                -- it's an internal option)
                                      (\h => "  " ++ optshow ++
                                             pack (List.replicate (minus (maxOpt + 2) (length optshow)) ' ') ++
                                             h ++ "\n")
                                      help

optsUsage : String
optsUsage = makeTextFromOptionsOrEnvs $ map optShow options

envsUsage : String
envsUsage = makeTextFromOptionsOrEnvs $ map (\e => (e.name, Just e.help)) envs

export
versionMsg : String
versionMsg = "Idris 2, version " ++ show version

export
usage : String
usage = """
  \{ versionMsg }
  Usage: idris2 [options] [input file]

  Available options:
  \{ optsUsage }
  Environment variables:
  \{ envsUsage }
  """

matchFlag : (d : OptDesc) -> List String ->
            Either String (Maybe (List CLOpt, List String))
matchFlag d [] = Right Nothing -- Nothing left to match
matchFlag d (x :: xs)
    = if x `elem` flags d
         then do args <- (action d).parse x xs
                 Right (Just args)
         else Right Nothing

findMatch : List OptDesc -> List String ->
            Either String (List CLOpt, List String)
findMatch [] [] = Right ([], [])
findMatch [] (f :: args) = case unpack f of
  '-' :: '-' :: _ => Left "Unknown flag \{f}"
  _ => Right ([InputFile f], args)
findMatch (d :: ds) args
    = case !(matchFlag d args) of
           Nothing => findMatch ds args
           Just res => Right res

parseOpts : List OptDesc -> List String -> Either String (List CLOpt)
parseOpts opts [] = Right []
parseOpts opts args
   = do (cl, rest) <- findMatch opts args
        cls <- assert_total (parseOpts opts rest) -- 'rest' smaller than 'args'
        pure (cl ++ cls)

export
getOpts : List String -> Either String (List CLOpt)
getOpts opts = parseOpts options opts

export covering
getCmdOpts : IO (Either String (List CLOpt))
getCmdOpts = do (_ :: opts) <- getArgs
                    | _ => pure (Left "Invalid command line")
                pure $ getOpts opts

||| Find an opt that would have matched if only the user had prefixed it with
||| double-dashes. It is common to see the user error of specifying a command
||| like "idris2 build ..." when they mean to write "idris2 --build ..."
export
findNearMatchOpt : String -> Maybe String
findNearMatchOpt arg =
  let argWithDashes = "--\{arg}"
  in
  case (getOpts [argWithDashes]) of
       Right [(InputFile _)] => Nothing
       Right [_] => Just argWithDashes
       _ => Nothing

||| Suggest an opt that would have matched if only the user had prefixed it with
||| double-dashes. It is common to see the user error of specifying a command
||| like "idris2 build ..." when they mean to write "idris2 --build ..."
export
nearMatchOptSuggestion : String -> Maybe (Doc IdrisAnn)
nearMatchOptSuggestion arg =
    findNearMatchOpt arg <&>
      \opt =>
        (reflow "Did you mean to type" <++>
          (dquotes . meta $ pretty0 opt) <+> "?")

||| List of all command line option flags.
export
optionFlags : List String
optionFlags = options >>= flags
