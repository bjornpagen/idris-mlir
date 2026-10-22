-- SPDX-License-Identifier: 0BSD
-- Copyright (c) 2026 Bjorn Pagen
||| The one committed manifest of the generated files: the fingerprint of the
||| specification's printed value, of the generator's sources, and of each
||| file's text. No generated file carries a stamp, so a file is rewritten
||| only when its bytes change and an edit recompiles only what it reaches;
||| `make check` regenerates and compares the files and this, so a hand edit
||| fails, and so does a generator changed without its outputs.
module IdrisMLIR.Spec.Generator.Manifest

import IdrisMLIR.Spec.Core.Text
import IdrisMLIR.Spec.Generator.Render

import Data.Bits
import Data.List
import Data.List1

%default total

||| FNV-1a over 64 bits: a pure function of the bytes, the same on both
||| hosts, which wrap a 64-bit product alike.
export
fnv : Bits64 -> List Bits8 -> Bits64
fnv h [] = h
fnv h (b :: bs) = fnv (xor h (cast b) * 0x100000001b3) bs

||| A text's fingerprint, sixteen hexadecimal digits: of its UTF-8, since the
||| specification's text is ASCII but a source file's comment may not be,
||| and both hosts read files as UTF-8.
export
fingerprint : String -> String
fingerprint s = hex64 (fnv 0xcbf29ce484222325 (utf8 s))

||| The manifest's text: the specification's and the generator's
||| fingerprints, then each output's, in the outputs' order.
export
manifest : (specification, generator : String) -> List (Path, String) -> String
manifest spec gen outs =
  render (["specification " ++ spec, "generator " ++ gen]
          ++ map (\(p, t) => fingerprint t ++ " " ++ pathText p) outs)

||| The manifest's path, beside the generated tree.
export
manifestPath : Path
manifestPath = "foreign" ::: ["idr", "generated.manifest"]

-- A check's verdict on a file is a line a person reads and a test of the
-- check reads back, so its wording is said here once: the test reads a
-- path with `differsNamed`, never by restating the words.
differsLead : String
differsLead = "specgen: differs from the specification: "

||| What a check says of a file whose committed text differs from what would
||| be written: one line naming its path.
export
differsLine : (path : String) -> String
differsLine path = differsLead ++ path

||| The path a check's line names as differing: `differsLine`'s inverse, and
||| nothing for any other line the check says.
export
differsNamed : String -> Maybe String
differsNamed line = pack <$> after (unpack differsLead) (unpack line)
  where
    after : List Char -> List Char -> Maybe (List Char)
    after [] rest = Just rest
    after (_ :: _) [] = Nothing
    after (c :: cs) (d :: ds) = if c == d then after cs ds else Nothing
