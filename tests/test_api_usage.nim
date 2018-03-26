import
  unittest, strutils,
  rlp, util/json_testing

proc q(s: string): string = "\"" & s & "\""
proc i(s: string): string = s.replace(" ").replace("\n")
proc inspectMatch(r: Rlp, s: string): bool = r.inspect.i == s.i

test "empty bytes are not a proper RLP":
  var rlp = rlpFromBytes Bytes(@[]).toRange

  check:
    not rlp.hasData
    not rlp.isBlob
    not rlp.isList
    not rlp.isEmpty

  expect Exception:
    discard rlp.getType

  expect Exception:
    for e in rlp:
      discard e.getType

test "you cannot finish a list without appending enough elements":
  var writer = initRlpList(3)
  writer.append "foo"
  writer.append "bar"

  expect PrematureFinalizationError:
    let result = writer.finish

proc withNewLines(x: string): string = x & "\n"

test "encode and decode lists":
  var writer = initRlpList(3)
  writer.append "foo"
  writer.append ["bar", "baz"]
  writer.append [30, 40, 50]

  var
    bytes = writer.finish
    rlp = rlpFromBytes bytes

  check:
    bytes.hexRepr == "d183666f6fc8836261728362617ac31e2832"
    rlp.inspectMatch """
      {
        "foo"
        {
          "bar"
          "baz"
        }
        {
          byte 30
          byte 40
          byte 50
        }
      }
    """

  bytes = encodeList(6000,
                     "Lorem ipsum dolor sit amet",
                     "Donec ligula tortor, egestas eu est vitae")

  rlp = rlpFromBytes bytes
  check:
    rlp.listLen == 3
    rlp.listElem(0).toInt(int) == 6000
    rlp.listElem(1).toString == "Lorem ipsum dolor sit amet"
    rlp.listElem(2).toString == "Donec ligula tortor, egestas eu est vitae"

test "toBytes":
  let rlp = rlpFromHex("f2cb847f000001827666827666a040ef02798f211da2e8173d37f255be908871ae65060dbb2f77fb29c0421447f4845ab90b50")
  let tok = rlp.listElem(1).toBytes()
  check:
    tok.len == 32
    tok.hexRepr == "40ef02798f211da2e8173d37f255be908871ae65060dbb2f77fb29c0421447f4"

test "nested lists":
  let listBytes = encode([[1, 2, 3], [5, 6, 7]])
  let listRlp = rlpFromBytes listBytes
  let sublistRlp0 = listRlp.listElem(0)
  let sublistRlp1 = listRlp.listElem(1)
  check sublistRlp0.listElem(0).toInt(int) == 1
  check sublistRlp0.listElem(1).toInt(int) == 2
  check sublistRlp0.listElem(2).toInt(int) == 3
  check sublistRlp1.listElem(0).toInt(int) == 5
  check sublistRlp1.listElem(1).toInt(int) == 6
  check sublistRlp1.listElem(2).toInt(int) == 7

test "encoding length":
  let listBytes = encode([1,2,3,4,5])
  let listRlp = rlpFromBytes listBytes
  check listRlp.listLen == 5

  let emptyListBytes = encode ""
  check emptyListBytes.len == 1
  let emptyListRlp = rlpFromBytes emptyListBytes
  check emptyListRlp.blobLen == 0

test "basic decoding":
  var rlp = rlpFromHex("856d6f6f7365")
  check rlp.inspect == q"moose"

test "malformed/truncated RLP":
  var rlp = rlpFromHex("b8056d6f6f7365")
  expect MalformedRlpError:
    discard rlp.inspect
