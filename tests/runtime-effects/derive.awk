# SPDX-License-Identifier: 0BSD
# Copyright (c) 2026 Bjorn Pagen
# What each runtime function an op calls does, as LLVM reads the runtime's
# own code: the module opt prints after inferring every function's
# attributes from its body. Its input is the declared table (runtests
# --runtime-effects), which names the functions and the endings, then the
# module's text. One line per function the table names, in its order:
#
#     fn <symbol> missing
#     fn <symbol> <noreturn> <crashes> <exits> <memory> <written>
#
# noreturn: LLVM proved it never returns. crashes, exits: it reaches,
# through the calls of the module's functions, the function the runtime
# ends a process through for an ending of a crash's kind, or of an exit.
# memory: what LLVM proved it does to memory, `none`, `reads` or `writes`;
# `unknown` where it reaches a call LLVM knows nothing of (a function
# outside the module with no stated effects, a call through a pointer),
# since then the absence of a stated effect proves nothing. written: the
# parameters, from 0, of pointer type, through which it may write and
# which it never lets go of, comma-separated, or `-`: what such a
# parameter points to is written by this function's own code. Then one
# line per ending: `ending <kind> <name> present|absent`.
#
# The runtime ends a process in one function per ending type, the template
# rt::end::end instantiated for it, whose name its type's name fixes: void
# rt::end::end<rt::end::NAME>(rt::end::NAME const&), mangled below.

function endingSymbol(name) { return "_ZN2rt3end3endINS0_" length(name) name "EEEvRKT_" }

# The name of the first function a line names before its parameters,
# `@name(` or `@"name"(`, without the sigil and quotes; empty where none.
function nameAt(s,   m) {
  if (!match(s, /@("[^"]*"|[-A-Za-z0-9_.$]+)\(/))
    return ""
  m = substr(s, RSTART + 1, RLENGTH - 2)
  gsub(/"/, "", m)
  return m
}

# The parameters of the function a define line names, split at the commas
# outside brackets, into params[1..n]; paramsEnd is where the list closes.
function splitParams(s,   start, depth, i, c, cur, n) {
  start = RSTART + RLENGTH
  n = 0
  depth = 0
  cur = ""
  for (i = start; i <= length(s); i++) {
    c = substr(s, i, 1)
    if (c == "(" || c == "{" || c == "[" || c == "<") {
      depth++
    } else if (c == ")" || c == "}" || c == "]" || c == ">") {
      if (depth == 0) {
        if (cur ~ /[^ ]/)
          params[++n] = cur
        paramsEnd = i
        return n
      }
      depth--
    } else if (c == "," && depth == 0) {
      params[++n] = cur
      cur = ""
      continue
    }
    cur = cur c
  }
  paramsEnd = length(s)
  return n
}

# Whether a parameter is a pointer the function writes through and never
# lets go of: of pointer type, neither readonly nor readnone, and not
# captured.
function writtenParam(p) {
  if (p !~ /(^| )ptr( |$)/)
    return 0
  if (p ~ /(^| )read(only|none)( |$)/)
    return 0
  return p ~ /(^| )nocapture( |$)/ || p ~ /captures\(none\)/
}

# The callee of a call or invoke instruction: `@name`, `%value` for a call
# through a pointer, `?` for one with no callee LLVM names (inline
# assembly), or empty for a line that calls nothing.
function calleeOf(s,   rest) {
  if (!match(s, /(^|[ =])(tail |musttail |notail )?(call|invoke) /))
    return ""
  rest = substr(s, RSTART + RLENGTH)
  if (!match(rest, /[@%]("[^"]*"|[-A-Za-z0-9_.$]+)\(/))
    return "?"
  rest = substr(rest, RSTART, RLENGTH - 1)
  gsub(/"/, "", rest)
  return rest
}

# What a memory attribute's text says, none, reads or writes: writes when
# any location may be written, else reads when any may be read.
function memoryOf(spec,   n, parts, i, access, w, r) {
  n = split(spec, parts, /, */)
  w = 0
  r = 0
  for (i = 1; i <= n; i++) {
    access = parts[i]
    sub(/^[^:]*: */, "", access)
    if (access ~ /write/)
      w = 1
    if (access ~ /read/)
      r = 1
  }
  return w ? "writes" : r ? "reads" : "none"
}

FNR == NR {
  if ($1 == "op" && !($2 in wanted)) {
    wanted[$2] = 1
    order[++wantedCount] = $2
  } else if ($1 == "ending") {
    ++endingCount
    endingKind[endingCount] = $2
    endingName[endingCount] = $3
    endingOf[endingSymbol($3)] = $2
  }
  next
}

/^define / {
  current = nameAt($0)
  defined[current] = 1
  n = splitParams($0)
  if (current in wanted) {
    list = ""
    for (k = 1; k <= n; k++)
      if (writtenParam(params[k]))
        list = list (list == "" ? "" : ",") (k - 1)
    written[current] = list == "" ? "-" : list
  }
  rest = substr($0, paramsEnd + 1)
  if (match(rest, /#[0-9]+/))
    group[current] = substr(rest, RSTART + 1, RLENGTH - 1)
  next
}

/^declare / {
  name = nameAt($0)
  external[name] = 1
  n = splitParams($0)
  rest = substr($0, paramsEnd + 1)
  if (match(rest, /#[0-9]+/))
    group[name] = substr(rest, RSTART + 1, RLENGTH - 1)
  next
}

/^attributes #[0-9]+ = \{/ {
  id = $2
  sub(/^#/, "", id)
  attribute[id] = $0
  next
}

current != "" && /^}/ {
  current = ""
  next
}

current != "" {
  callee = calleeOf($0)
  if (callee == "")
    next
  if (callee == "?" || callee ~ /^%/) {
    opaque[current] = 1
    next
  }
  callee = substr(callee, 2)
  # An intrinsic's effects are LLVM's own, known to it.
  if (callee ~ /^llvm\./)
    next
  edges[current] = edges[current] " " callee
}

# The attribute text of a function, empty where it has none.
function attributesOf(name) { return (name in group) ? attribute[group[name]] : "" }

function hasMemory(text) { return match(text, /memory\([^)]*\)/) }

END {
  # A function outside the module whose effects nothing states is a call
  # LLVM knows nothing of.
  for (name in external)
    if (!hasMemory(attributesOf(name)))
      opaque[name] = 1

  for (w = 1; w <= wantedCount; w++) {
    symbol = order[w]
    if (!(symbol in defined)) {
      print "fn", symbol, "missing"
      continue
    }
    # Every function the symbol reaches by calls, itself included.
    split("", seen)
    count = 1
    queue[1] = symbol
    seen[symbol] = 1
    unknown = 0
    crashes = "no"
    exits = "no"
    for (at = 1; at <= count; at++) {
      u = queue[at]
      if (u in opaque)
        unknown = 1
      m = split(edges[u], callees, " ")
      for (c = 1; c <= m; c++) {
        v = callees[c]
        if (v in endingOf) {
          if (endingOf[v] == "crash")
            crashes = "yes"
          else if (endingOf[v] == "exit")
            exits = "yes"
        }
        if (!(v in seen)) {
          seen[v] = 1
          queue[++count] = v
        }
      }
    }
    text = attributesOf(symbol)
    noreturn = text ~ /[ {]noreturn[ }]/ ? "yes" : "no"
    if (hasMemory(text)) {
      spec = substr(text, RSTART + 7, RLENGTH - 8)
      memory = memoryOf(spec)
    } else {
      memory = unknown ? "unknown" : "writes"
    }
    print "fn", symbol, noreturn, crashes, exits, memory, written[symbol]
  }

  for (e = 1; e <= endingCount; e++)
    print "ending", endingKind[e], endingName[e], ((endingSymbol(endingName[e]) in defined) ? "present" : "absent")
}
