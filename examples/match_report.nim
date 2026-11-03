## Prints every match with pattern, offsets and matched text.
import ahocorasick

const pats = @["cat", "cats", "tomcat", "dog"]
let ac = initAhoCorasick(pats)
let text = "tomcats and dogs, a cat and a tomcat"

echo "text:    ", text
echo "patterns: ", pats
echo "---"
for m in ac.findAll(text):
  echo "pattern #", m.patternIndex, " (", pats[m.patternIndex],
    ") at bytes ", m.start, "..", m.last,
    " -> ", text[m.start .. m.last]
