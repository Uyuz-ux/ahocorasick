# ahocorasick

Aho-Corasick multi-pattern string search for Nim.

Build an automaton once from a set of literal patterns, then scan any
amount of text in a **single left-to-right pass**. Every occurrence of
every pattern is reported - including overlapping and nested matches,
which single-pattern `strutils.find` loops tend to skip.

Typical uses: keyword filters over log streams, sensitive-word scans,
routing on many prefixes, quick corpus statistics.

## Install

```
nimble install ahocorasick
```

Requires Nim >= 1.6. No dependencies beyond the standard library.

## Usage

```nim
import ahocorasick

let ac = initAhoCorasick(@["he", "she", "his", "hers"])

for m in ac.search("ushers"):
  echo m.patternIndex, " at bytes ", m.start, "..", m.last
# 1 at bytes 1..3   (she)
# 0 at bytes 2..3   (he)
# 3 at bytes 2..5   (hers)
```

Eager and boolean forms:

```nim
let all = ac.findAll("ushers")        # seq[Match]
let hit = ac.containsAny("ushers")    # true, exits at the first hit
```

See `examples/` for complete runnable programs: a log-line filter and a
match report over a sample text.

## API

| Signature | What it does |
|---|---|
| `initAhoCorasick(patterns: openArray[string]): AhoCorasick` | Builds the automaton. Raises `ValueError` on empty or duplicate patterns. |
| `iterator search(a, text: string): Match` | One pass over `text`; yields every occurrence, overlapping included. |
| `findAll(a, text: string): seq[Match]` | Eager `search`. |
| `containsAny(a, text: string): bool` | True when any pattern occurs; early exit on first hit. |
| `len(a): int` | Number of patterns in the automaton. |

`Match` fields: `patternIndex` (index into the pattern list),
`start` and `last` (inclusive byte offsets).

## Semantics and guarantees

- **Nothing is skipped.** Matches are reported by end position; matches
  ending at the same position come longest-first.
- **Byte offsets, UTF-8 safe.** Matching is byte-oriented; because
  UTF-8 is self-synchronizing, a byte-level match in valid UTF-8 text
  can never start mid-code-point, so offsets always fall on code point
  boundaries.
- **Case sensitive by design.** Matching is byte-exact; add
  case-folded patterns yourself if you need case insensitivity.
- **Deterministic.** No randomness, no locale, stable across platforms.

## Tests

```
nimble test
```

The suite includes a cross-check of the automaton against a brute-force
reference implementation over two corpora.

## License

MIT
