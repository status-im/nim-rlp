mode = ScriptMode.Verbose

packageName   = "rlp"
version       = "1.0.1"
author        = "Status Research & Development GmbH"
description   = "RLP serialization library for Nim"
license       = "Apache License 2.0"
skipDirs      = @["tests"]
bin           = @["rlp/bin/rlp_inspect"]
# avoid being considered a binary-only package: https://github.com/nim-lang/nimble/blob/66d79bf9a0970542351988fa31f487a1e70144f7/src/nimblepkg/packageparser.nim#L280
installExt    = @["nim"]

requires "nim >= 0.17.0",
         "ranges"

proc configForTests() =
  --hints: off
  --debuginfo
  --path: "."
  --run

task test, "run CPU tests":
  configForTests()
  setCommand "c", "tests/all.nim"
