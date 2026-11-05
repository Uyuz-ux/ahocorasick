## Aho-Corasick multi-pattern string search for Nim.
##
## Build an automaton once from a set of literal patterns, then scan any
## amount of text in a single pass. Every occurrence of every pattern is
## reported, including overlapping and nested ones - nothing is skipped
## after a hit.
##
##   import ahocorasick
##
##   let ac = initAhoCorasick(@["cat", "cats", "tomcat"])
##   for m in ac.search("tomcats and dogs"):
##     echo m.patternIndex, " at ", m.start, "..", m.last
##
## Matching is byte-oriented. Patterns and text may contain any bytes;
## for valid UTF-8 input, a byte-level match cannot begin in the middle
## of a code point (UTF-8 is self-synchronizing), so reported offsets
## always fall on code point boundaries of the text.
##
## Unrestricted license.

import std/[tables, strutils, algorithm]

type
  Match* = object
    patternIndex*: int ## Index of the matched pattern in the sequence
                       ## passed to `initAhoCorasick`.
    start*: int        ## Byte offset of the first byte of the match.
    last*: int         ## Byte offset of the last byte of the match.

  Node = object
    nxt: Table[uint8, int] ## Goto transitions on bytes.
    fail: int              ## Longest proper suffix that is still a trie prefix.
    outLink: int           ## Nearest terminal node reachable via suffix
                           ## links; -1 when none exists.
    patIdx: int            ## Pattern index for terminal nodes; -1 otherwise.
    patLen: int            ## Byte length of the pattern, for terminal nodes.

  AhoCorasick* = object
    ## Immutable multi-pattern matcher. Build it once, reuse it for many
    ## searches. A plain value type: copyable, with no heap aliasing.
    nodes: seq[Node]
    nPatterns: int

proc freshNode(): Node =
  ## A new, non-terminal node with no transitions.
  result.nxt = initTable[uint8, int]()
  result.fail = 0
  result.outLink = -1
  result.patIdx = -1
  result.patLen = 0

proc initAhoCorasick*(patterns: openArray[string]): AhoCorasick =
  ## Builds the automaton from `patterns`.
  ##
  ## Raises `ValueError` when the pattern list contains an empty string or
  ## a duplicate. The automaton holds one node per distinct pattern
  ## prefix, so memory scales with the total pattern text, not with the
  ## alphabet.
  runnableExamples:
    let ac = initAhoCorasick(@["he", "she", "his", "hers"])
    assert ac.containsAny("ushers")
    assert not ac.containsAny("dogs")

  # Validate first, so a bad input leaves nothing half-built.
  var seen = initTable[string, int]()
  for idx, pat in patterns:
    if pat.len == 0:
      raise newException(ValueError,
        "empty pattern at index " & $idx & " is not supported")
    if seen.hasKey(pat):
      raise newException(ValueError,
        "duplicate pattern " & pat.escape & " (indices " &
        $seen[pat] & " and " & $idx & ")")
    seen[pat] = idx

  result.nodes = @[freshNode()]
  result.nPatterns = patterns.len

  # Phase 1: trie insertion.
  for idx, pat in patterns:
    var state = 0
    for i in 0 ..< pat.len:
      let c = uint8(pat[i])
      if result.nodes[state].nxt.hasKey(c):
        state = result.nodes[state].nxt[c]
      else:
        result.nodes.add(freshNode())
        let id = result.nodes.len - 1
        result.nodes[state].nxt[c] = id
        state = id
    result.nodes[state].patIdx = idx
    result.nodes[state].patLen = pat.len

  # Phase 2: breadth-first pass for failure and output links. The queue
  # carries the node, its parent and the byte that led to it.
  var bfs: seq[tuple[u, parent: int, ch: uint8]] = @[]
  for c, v in result.nodes[0].nxt:
    bfs.add((v, 0, c))

  var bi = 0
  while bi < bfs.len:
    let (u, parent, ch) = bfs[bi]
    bi.inc

    # Failure link: the deepest proper suffix of u's label that is still
    # a trie prefix. Found by following the parent's failure chain.
    if parent == 0:
      result.nodes[u].fail = 0
    else:
      var f = result.nodes[parent].fail
      while true:
        if result.nodes[f].nxt.hasKey(ch):
          result.nodes[u].fail = result.nodes[f].nxt[ch]
          break
        if f == 0:
          result.nodes[u].fail = 0
          break
        f = result.nodes[f].fail

    # Output link: nearest terminal node on u's failure chain. The chain
    # ends at the root, which is never terminal (empty patterns are
    # rejected), so the walk terminates.
    let f = result.nodes[u].fail
    if result.nodes[f].patIdx >= 0:
      result.nodes[u].outLink = f
    else:
      result.nodes[u].outLink = result.nodes[f].outLink

    for c, v in result.nodes[u].nxt:
      bfs.add((v, u, c))

proc step(nodes: seq[Node], state: int, c: uint8): int =
  ## Goto function with failure fallback. Always yields a valid state.
  var s = state
  while true:
    if nodes[s].nxt.hasKey(c):
      return nodes[s].nxt[c]
    if s == 0:
      return 0
    s = nodes[s].fail

iterator search*(a: AhoCorasick, text: string): Match =
  ## Yields every occurrence of every pattern in `text` during one
  ## left-to-right pass. Overlapping and nested matches are all reported.
  ##
  ## Matches ending at the same byte position are yielded from the
  ## longest to the shortest. Offsets are byte offsets; `start` and
  ## `last` are both inclusive.
  var state = 0
  for i in 0 ..< text.len:
    state = step(a.nodes, state, uint8(text[i]))
    var s = state
    while s > 0:
      if a.nodes[s].patIdx >= 0:
        yield Match(
          patternIndex: a.nodes[s].patIdx,
          start: i - a.nodes[s].patLen + 1,
          last: i)
      s = a.nodes[s].outLink

proc findAll*(a: AhoCorasick, text: string): seq[Match] =
  ## Eager version of `search`. The result is ordered by match end
  ## position, longest-first within the same position.
  result = @[]
  for m in a.search(text):
    result.add(m)

proc containsAny*(a: AhoCorasick, text: string): bool =
  ## True when at least one pattern occurs in `text`. Exits at the first
  ## hit, so it doubles as a cheap membership test over a fixed set.
  for m in a.search(text):
    discard m
    return true
  false

proc len*(a: AhoCorasick): int =
  ## Number of patterns in the automaton.
  a.nPatterns

proc keptMatches(a: AhoCorasick; text: string): seq[Match] =
  ## Leftmost-longest selection over all occurrences in `text`: at each
  ## scan position the longest pattern that starts there wins, and the
  ## scan resumes right after it. Overlapping shorter matches are
  ## dropped, not re-entered.
  var best = initTable[int, Match]() # start -> longest match starting there
  for m in a.search(text):
    if m.last > best.getOrDefault(m.start,
        Match(patternIndex: -1, start: -1, last: -1)).last:
      best[m.start] = m
  var starts: seq[int]
  for s in keys(best):
    starts.add(s)
  sort(starts)
  var prevLast = -1
  for s in starts:
    if s > prevLast:
      let m = best[s]
      result.add(m)
      prevLast = m.last

proc replace*(a: AhoCorasick; text: string; replacement: string): string =
  ## Scan `text` and replace every match with `replacement`.
  ##
  ## Matches are chosen leftmost-longest: scanning conceptually moves
  ## left to right, takes the longest pattern starting at each position,
  ## and resumes right after it. Overlapping shorter matches are never
  ## re-entered - with patterns @["cat", "cats"], "cats" is replaced
  ## once by the `cats` rule, not twice. Use `findAll` directly when you
  ## need every occurrence instead.
  ##
  ## Offsets stay on UTF-8 code point boundaries for valid UTF-8 input,
  ## so whole-code-point replacements never tear a character apart.
  let kept = keptMatches(a, text)
  result = newStringOfCap(text.len)
  var pos = 0
  for m in kept:
    result.add(text[pos ..< m.start])
    result.add(replacement)
    pos = m.last + 1
  if pos <= text.high:
    result.add(text[pos .. text.high])

proc replace*(a: AhoCorasick; text: string;
              mapping: proc (m: Match): string): string =
  ## Overload that computes the replacement per kept match. `mapping`
  ## receives each leftmost-longest `Match` (patternIndex, start, last)
  ## and returns the text to substitute it with.
  let kept = keptMatches(a, text)
  result = newStringOfCap(text.len)
  var pos = 0
  for m in kept:
    result.add(text[pos ..< m.start])
    result.add(mapping(m))
    pos = m.last + 1
  if pos <= text.high:
    result.add(text[pos .. text.high])
