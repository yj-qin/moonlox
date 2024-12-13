///|
fn clock_native(_arg_count : Int, _args : FixedArray[Value]) -> Value {
  NumberVal(now().to_double() / 1000)
}
