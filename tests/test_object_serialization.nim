import
  unittest, times, rlp, util/json_testing

type
  Transaction = object
    amount: int
    time: DateTime
    sender: string
    receiver: string

  Foo = object
    x: uint64
    y: string
    z: seq[int]

  Bar = object
    b: string
    f: Foo

  CompressedFoo = object

  Bar2 = object
    f {.rlpCustomSerialization: CompressedFoo}: Foo

rlpFields Foo,
  x, y, z

rlpFields Transaction,
  sender, receiver, amount

proc default(T: typedesc): T = discard

proc append*(rlpWriter: var RlpWriter, f: Foo, tag: type CompressedFoo) =
  rlpWriter.append(f.x)
  rlpWriter.append(f.y.len)

proc read*(rlp: var Rlp, T: type Foo, tag: type CompressedFoo): Foo =
  result.x = rlp.read(uint64)
  result.y = newString(rlp.read(int))

test "encoding and decoding an object":
  var originalBar = Bar(b: "abracadabra",
                        f: Foo(x: 5'u64, y: "hocus pocus", z: @[100, 200, 300]))

  var bytes = encode(originalBar)
  var r = rlpFromBytes(bytes)
  var restoredBar = r.read(Bar)

  check:
    originalBar == restoredBar

  var t1 = Transaction(time: now(), amount: 1000, sender: "Alice", receiver: "Bob")
  bytes = encode(t1)
  var t2 = bytes.decode(Transaction)

  check:
    bytes.hexRepr == "cd85416c69636583426f628203e8" # verifies that Alice comes first
    t2.time == default(DateTime)
    t2.sender == "Alice"
    t2.receiver == "Bob"
    t2.amount == 1000

test "custom field serialization":
  var origVal = Bar2(f: Foo(x: 10'u64, y: "y", z: @[]))
  var bytes = encode(origVal)
  var r = rlpFromBytes(bytes)
  var restored = r.read(Bar2)

  check:
    origVal.f.x == restored.f.x
    origVal.f.y.len == restored.f.y.len

