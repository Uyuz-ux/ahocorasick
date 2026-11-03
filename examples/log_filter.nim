## Filters a fixed set of keywords out of a log snippet.
## The automaton is built once and reused for every line.
import ahocorasick, strutils

const log = """
2026-11-04 09:12:01 INFO  service started
2026-11-04 09:12:07 WARN  retrying db connection (timeout=30s)
2026-11-04 09:12:09 ERROR upstream refused connection
2026-11-04 09:12:15 INFO  healthy again
"""

const keywords = @["WARN", "ERROR", "timeout", "refused"]
let ac = initAhoCorasick(keywords)

echo "Scanning for: ", keywords.join(", ")
echo "---"
for line in log.splitLines():
  if line.len == 0:
    continue
  if ac.containsAny(line):
    echo line
