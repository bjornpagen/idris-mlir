-- SPDX-License-Identifier: BSD-3-Clause
-- Copyright (c) 2020 Edwin Brady
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
  AltErrorCount Nat |
   ||| Treat warnings as errors
  WarningsAsErrors |
   ||| Do not print shadowing warnings
  IgnoreShadowingWarnings |
   ||| Turn on %default total globally
  Total

||| An option's argument, if it takes one, with what the option means given
||| the argument's value: every option takes at most one. Each case names
||| the type of the value its action is given, so no type is computed from a
||| description of the arguments.
data OptArg
  = NoArg (List CLOpt)
   | Required String (String -> List CLOpt)
   | Optional String (Maybe String -> List CLOpt)
   | RequiredNat String (Nat -> List CLOpt)
   | AutoNat String (Maybe Nat -> List CLOpt)
   | RequiredLogLevel String (LogLevel -> List CLOpt)

||| How the usage text shows an option's argument.
showArg : OptArg -> String
showArg (NoArg _) = ""
showArg (Required a _) = "<" ++ a ++ ">"
showArg (RequiredNat a _) = "<" ++ a ++ ">"
showArg (RequiredLogLevel a _) = "<" ++ a ++ ">"
showArg (Optional a _) = "[" ++ a ++ "]"
showArg (AutoNat a _) = "<" ++ a ++ ">"

record OptDesc where
  constructor MkOpt
  flags : List String
  arg : OptArg
  help : Maybe String

optSeparator : OptDesc
optSeparator = MkOpt [] (NoArg []) Nothing

showDefault : Show a => a -> String
showDefault x = "(default " ++ show x ++ ")"

options : List OptDesc
options = [MkOpt ["--check", "-c"] (NoArg [CheckOnly])
              (Just "Exit after checking source file"),
           MkOpt ["--output", "-o"] (Required "file" (\f => [OutputFile f, Quiet]))
              (Just "Specify output file"),
           MkOpt ["--exec", "-x"] (Required "name" (\f => [ExecFn f, Quiet]))
              (Just "Execute expression"),
           MkOpt ["--no-prelude"] (NoArg [NoPrelude])
              (Just "Don't implicitly import Prelude"),
           MkOpt ["--codegen", "--cg"] (Required "backend" (\f => [SetCG f]))
              (Just "Set code generator"),
           MkOpt ["--directive"] (Required "directive" (\d => [Directive d]))
              (Just $ "Pass a directive to the current code generator"),
           MkOpt ["--package", "-p"] (Required "package" (\f => [PkgPath f]))
              (Just "Add a package as a dependency"),
           MkOpt ["--source-dir"] (Required "dir" (\d => [SourceDir d]))
              (Just $ "Set source directory"),
           MkOpt ["--build-dir"] (Required "dir" (\d => [BuildDir d]))
              (Just $ "Set build directory"),
           MkOpt ["--output-dir"] (Required "dir" (\d => [OutputDir d]))
              (Just $ "Set output directory"),

           optSeparator,
           MkOpt ["--total"] (NoArg [Total])
              (Just "Require functions to be total by default"),
           MkOpt ["-Werror"] (NoArg [WarningsAsErrors])
              (Just "Treat warnings as errors"),
           MkOpt ["-Wno-shadowing"] (NoArg [IgnoreShadowingWarnings])
              (Just "Do not print shadowing warnings"),

           optSeparator,
           MkOpt ["--prefix"] (NoArg [Directory Prefix])
              (Just "Show installation prefix"),
           MkOpt ["--paths"] (NoArg [Directory BlodwenPaths])
              (Just "Show paths"),
           MkOpt ["--libdir"] (NoArg [Directory LibDir])
              (Just "Show library directory"),
           MkOpt ["--list-packages"] (NoArg [ListPackages])
              (Just "List installed packages"),

           optSeparator,
           MkOpt ["--dump-installdir"] (Optional "package file"
              (\ f => [Package DumpInstallDir f]))
              (Just "Dump the location where the given package will be installed"),
           MkOpt ["--build"] (Optional "package file"
               (\f => [Package Build f]))
              (Just "Build modules/executable for the given package"),
           MkOpt ["--install"] (Optional "package file"
              (\f => [Package Install f]))
              (Just "Install the given package"),
           MkOpt ["--install-with-src"] (Optional "package file"
              (\f => [Package InstallWithSrc f]))
              (Just "Install the given package"),
           MkOpt ["--typecheck"] (Optional "package file"
              (\f => [Package Typecheck f]))
              (Just "Typechecks the given package without code generation"),
           MkOpt ["--clean"] (Optional "package file" (\f => [Package Clean f]))
              (Just "Clean intermediate files/executables for the given package"),
           MkOpt ["--find-ipkg"] (NoArg [FindIPKG])
              (Just "Find and use an .ipkg file in a parent directory."),
           MkOpt ["--ignore-missing-ipkg"] (NoArg [IgnoreMissingIPKG])
              (Just "Fail silently if a dependency is missing."),

           optSeparator,
           MkOpt ["--timing"] (AutoNat "level" (\ n => [Timing n]))
              (Just "Display timing logs"),

           optSeparator,
           MkOpt ["--no-banner"] (NoArg [NoBanner])
              (Just "Suppress the banner"),
           MkOpt ["--quiet", "-q"] (NoArg [Quiet])
              (Just "Quiet mode; display fewer messages"),
           MkOpt ["--console-width"] (AutoNat "console width" (\l => [ConsoleWidth l]))
              (Just "Width for console output (0 for unbounded) (auto by default)"),
          MkOpt ["--show-implicits"] (NoArg [ShowImplicits])
              (Just "Show implicits when pretty printing"),
           MkOpt ["--show-machine-names"] (NoArg [ShowMachineNames])
              (Just "Show machine names when pretty printing"),
           MkOpt ["--show-namespaces"] (NoArg [ShowNamespaces])
              (Just "Show namespaces when pretty printing"),
           MkOpt ["--color", "--colour"] (NoArg ([Color True]))
              (Just "Forces colored console output (enabled by default)"),
           MkOpt ["--no-color", "--no-colour"] (NoArg ([Color False]))
              (Just "Disables colored console output"),
           MkOpt ["--verbose"] (NoArg [Verbose])
              (Just "Verbose mode (default)"),
           MkOpt ["--log"] (RequiredLogLevel "log level" (\l => [Logging l]))
              (Just "Global log level (0 by default)"),

           optSeparator,
           MkOpt ["--version", "-v"] (NoArg [Version])
              (Just "Display version string"),
           MkOpt ["--ttc-version"] (NoArg [TTCVersion])
              (Just "Display TTC version string"),
           MkOpt ["--help", "-h", "-?"] (Optional "topic" (\ tp => [Help (tp >>= recogniseHelpTopic)]))
              (Just "Display help text"),

           -- Internal debugging options
           MkOpt ["--alt-error-count"] (RequiredNat "alternative count" (\c => [AltErrorCount c]))
              (Just "Outputs errors for the given number of alternative parsing attempts.")
           ]

optShow : OptDesc -> (String, Maybe String)
optShow (MkOpt [] _ _) = ("", Just "")
optShow (MkOpt flags arg help) = (showSep ", " flags ++ " " ++ showArg arg, help)
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

checkNat : Integer -> Maybe Nat
checkNat n = toMaybe (n >= 0) (integerToNat n)

processArgs : String -> OptArg -> List String ->
              Either String (List CLOpt, List String)
processArgs flag (NoArg f) xs = Right (f, xs)
-- Missing required arguments
processArgs flag (Optional a f) [] = Right (f Nothing, [])
processArgs flag opt [] =
  Left $ "Missing required argument " ++ showArg opt ++ " for flag " ++ flag
-- Happy cases
processArgs flag (RequiredNat a f) (x :: xs) =
  do arg <- maybeToEither ("Expected Nat argument " ++ show x ++ " for flag " ++ flag)
                          (parseSigned x >>= checkNat)
     Right (f arg, xs)
processArgs flag (RequiredLogLevel a f) (x :: xs) =
  do arg <- maybeToEither ("Expected LogLevel argument " ++ show x ++ " for flag " ++ flag)
                          (parseLogLevel x)
     Right (f arg, xs)
processArgs flag (AutoNat a f) ("auto" :: xs) = Right (f Nothing, xs)
processArgs flag (AutoNat a f) (x :: xs) =
  do arg <- maybeToEither ("Expected Nat or \"auto\" argument " ++ show x ++ " for flag " ++ flag)
                          (parseSigned x >>= checkNat)
     Right (f (Just arg), xs)
processArgs flag (Required a f) (x :: xs) = Right (f x, xs)
processArgs flag (Optional a f) (x :: xs) =
  if isPrefixOf "-" x
    then Right (f Nothing, x :: xs)
    else Right (f $ Just x, xs)

matchFlag : (d : OptDesc) -> List String ->
            Either String (Maybe (List CLOpt, List String))
matchFlag d [] = Right Nothing -- Nothing left to match
matchFlag d (x :: xs)
    = if x `elem` flags d
         then do args <- processArgs x (arg d) xs
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
