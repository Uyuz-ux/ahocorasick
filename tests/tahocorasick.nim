## Tests for ahocorasick.
##
## Run with: nimble test
## (the nimble task compiles with --path:src)

import std/[unittest, algorithm, strutils, sequtils, tables]
import ahocorasick

type Key = tuple[start, last, patIdx: int]

proc key(m: Match): Key = (m.start, m.last, m.patternIndex)

proc sortedMs(ms: seq[Match]): seq[Key] =
  ## Canonical ordering for order-independent comparison.
  result = ms.mapIt(key(it))
  result.sort(proc(a, b: Key): int =
    if a.start != b.start: return cmp(a.start, b.start)
    if a.last != b.last: return cmp(a.last, b.last)
    cmp(a.patIdx, b.patIdx))

proc naiveMatches(pats: seq[string], text: string): seq[Key] =
  ## Brute-force reference: every (pattern, offset) pair that matches.
  for idx, p in pats:
    for i in 0 ..< text.len:
      if i + p.len <= text.len and text[i ..< i + p.len] == p:
        result.add((i, i + p.len - 1, idx))
  result.sort(proc(a, b: Key): int =
    if a.start != b.start: return cmp(a.start, b.start)
    if a.last != b.last: return cmp(a.last, b.last)
    cmp(a.patIdx, b.patIdx))

suite "ahocorasick":

  test "classic example: ushers finds she, he and hers":
    let ac = initAhoCorasick(@["he", "she", "his", "hers"])
    let got = sortedMs(ac.findAll("ushers"))
    check got == @[(1, 3, 1), (2, 3, 0), (2, 5, 3)]

  test "same pattern repeated, overlapping occurrences all found":
    let ac = initAhoCorasick(@["aa"])
    let got = sortedMs(ac.findAll("aaaa"))
    # (0,1), (1,2), (2,3) - nothing skipped after a hit.
    check got == @[(0, 1, 0), (1, 2, 0), (2, 3, 0)]

  test "search order: end positions left to right, longest first":
    let ac = initAhoCorasick(@["cat", "tomcat", "cats"])
    let got = ac.findAll("tomcats")
    # Position 5 ends both "tomcat" and "cat" (longest first);
    # position 6 ends "cats".
    check got == @[
      Match(patternIndex: 1, start: 0, last: 5),
      Match(patternIndex: 0, start: 3, last: 5),
      Match(patternIndex: 2, start: 3, last: 6)]

  test "nested patterns inside a longer word":
    let ac = initAhoCorasick(@["she", "he", "e"])
    let got = sortedMs(ac.findAll("she"))
    check got == @[(0, 2, 0), (1, 2, 1), (2, 2, 2)]

  test "utf-8 text: offsets stay on code point boundaries":
    let ac = initAhoCorasick(@["日本", "本語"])
    let text = "日本語"
    let ms = ac.findAll(text)
    check ms.len == 2
    # Both offsets pairs land on code point boundaries (0, 3, 6 bytes).
    for m in ms:
      check m.start mod 3 == 0
      check text[m.start .. m.last] == ["日本", "本語"][m.patternIndex]

  test "empty pattern raises ValueError":
    expect ValueError:
      discard initAhoCorasick(@["ok", ""])

  test "duplicate pattern raises ValueError":
    expect ValueError:
      discard initAhoCorasick(@["alpha", "beta", "alpha"])

  test "containsAny, len and no-match cases":
    let ac = initAhoCorasick(@["warn", "error", "panic"])
    check ac.len == 3
    check ac.containsAny("kernel panic at boot")
    check not ac.containsAny("all systems nominal")
    check ac.findAll("quiet log").len == 0
    # Pattern longer than the text.
    check not initAhoCorasick(@["warning"]).containsAny("warn")

  test "matching is byte-exact (case sensitive by design)":
    let ac = initAhoCorasick(@["Error"])
    check not ac.containsAny("error in module")
    check ac.containsAny("severity=Error found")
    let lower = initAhoCorasick(@["error"])
    check lower.containsAny("error in module")

  test "cross-check against brute force on a mixed corpus":
    let pats = @["nim", "mni", "im", "lang", "galn", "a", "nimlang",
                 "gn", "angla", "nil"]
    var text = "nimlanglangmni angla galn nil nim im mni langnim"
    # Pad with filler so both prefix and suffix matches appear.
    text = "xx" & text & "yy"
    let ac = initAhoCorasick(pats)
    check sortedMs(ac.findAll(text)) == naiveMatches(pats, text)
    # And a second corpus without any pattern except single letters.
    let text2 = "zzz qqq www kkk"
    check sortedMs(ac.findAll(text2)) == naiveMatches(pats, text2)
