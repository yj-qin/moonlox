///|
typealias Value = Double

///|
struct ValueArray {
  values : Array[Value]
}

///|
fn ValueArray::new() -> ValueArray {
  { values: [] }
}

///|
fn add_value(self : ValueArray, value : Value) -> Unit {
  self.values.push(value)
}
