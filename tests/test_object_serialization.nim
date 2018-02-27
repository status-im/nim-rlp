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

rlpFields Foo,
  x, y, z

rlpFields Transaction,
  sender, receiver, amount

proc default(T: typedesc): T = discard

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
    bytes.hexRepr == "85416c69636583426f628203e8" # verifies that Alice comes first
    t2.time == default(DateTime)
    t2.sender == "Alice"
    t2.receiver == "Bob"
    t2.amount == 1000

