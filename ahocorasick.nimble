# Package

version       = "0.2.0"
author        = "Uyuz-ux"
description   = "Aho-Corasick multi-pattern string search: report every occurrence of every pattern in one pass"
license       = "MIT"
srcDir        = "src"

# Dependencies

requires "nim >= 1.6"

# Tests

task test, "Runs the test suite":
  exec "nim c -r --path:src tests/tahocorasick.nim"
