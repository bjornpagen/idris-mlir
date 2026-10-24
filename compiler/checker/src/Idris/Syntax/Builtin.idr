-- SPDX-License-Identifier: BSD-3-Clause
-- Copyright (c) 2020 Edwin Brady
module Idris.Syntax.Builtin

import Core.Name

%default total

export
pairname : Name
pairname = NS builtinNS (knownUN KPair)

export
mkpairname : Name
mkpairname = NS builtinNS (knownUN KMkPair)

export
dpairname : Name
dpairname = NS dpairNS (knownUN KDPair)

export
mkdpairname : Name
mkdpairname = NS dpairNS (knownUN KMkDPair)

export
nilName : Name
nilName = NS preludeNS (knownUN KNil)

export
consName : Name
consName = NS preludeNS (knownUN KCons)

export
interpolateName : Name
interpolateName = NS preludeNS (knownUN Kinterpolate)

export
eqName : Name
eqName = NS builtinNS (knownUN KHomoEq)
