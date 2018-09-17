import macros

template enumerateRlpFields*[T](x: T, op: untyped) =
  for f in fields(x): op(f)

macro rlpFields*(T: typedesc, fields: varargs[untyped]): untyped =
  var body = newStmtList()
  let
    ins = genSym(nskParam, "instance")
    op = genSym(nskParam, "op")

  for field in fields:
    body.add quote do: `op`(`ins`.`field`)

  result = quote do:
    template enumerateRlpFields*(`ins`: `T`, `op`: untyped) {.inject.} =
      `body`

template rlpInline* {.pragma.}
  ## This can be specified on a record field in order to avoid the
  ## default behavior of wrapping the record in a RLP list.

template rlpCustomSerialization*(T: typedesc) {.pragma.}
  ## This can be specified on a record field to trigger the use of a
  ## custom `read` and `append` serialization functions.
  ## The custom functions will be passed an additional `type` argument
  ## specefied in the pragma (it is used as an overload tag)

