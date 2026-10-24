-- SPDX-License-Identifier: BSD-3-Clause
-- Copyright (c) 2020 Edwin Brady
||| Provides semantic versioning `Version` type and utilities.
||| See [semver](https://semver.org/) for proper definition of semantic versioning
module Libraries.Data.Version

import Data.String

import Libraries.Text.Parser
import Libraries.Text.Lexer

%default total

||| Semantic versioning with optional tag
public export
record Version where
  constructor MkVersion
  ||| Semantic version
  ||| Should follow the (major, minor, patch) convention
  semVer : (Nat, Nat, Nat)
  ||| Optional tag
  ||| Usually contains git sha1 of this software's build in between releases
  versionTag : Maybe String

||| String representation of a Version with optional display of `tag`
export
showVersion : Bool -> Version -> String
showVersion tag (MkVersion (maj,min,patch) versionTag) =
  concat (intersperse "." (map show [ maj, min, patch])) ++
         if tag then showTag else ""
  where
    showTag : String
    showTag = case versionTag of
                Nothing => ""
                Just tag => "-" ++ tag

export
Show Version where
  show = showVersion True

export
Eq Version where
  (==) (MkVersion ver tag) (MkVersion ver' tag') = ver == ver' && tag == tag'

export
Ord Version where
  compare (MkVersion ver tag) (MkVersion ver' tag')  =
    case compare ver ver' of
      EQ => compare tag tag'
      other => other

--------------------------------------------------------------------------------
-- Parser
--------------------------------------------------------------------------------

data VersionTokenKind = VersionText | VersionNum | VersionDot | VersionDash

Eq VersionTokenKind where
  (==) VersionText VersionText = True
  (==) VersionNum VersionNum = True
  (==) VersionDot VersionDot = True
  (==) VersionDash VersionDash = True
  (==) _ _ = False


VersionToken : Type
VersionToken = Token VersionTokenKind

-- A number: its text, read as a natural.
number : Grammar () VersionToken n r True Nat
number = stringToNatOrZ <$> match VersionNum
