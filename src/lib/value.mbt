///|
priv enum FunctionKind {
  Function
  Method
  Initializer
  Script
} derive(Show, Eq)

///|
priv struct Function {
  mut arity : Int
  name : String
  mut upvalue_count : Int
  chunk : Chunk
} derive(Show)

///|
fn Function::new(name~ : String = "") -> Function {
  { arity: 0, upvalue_count: 0, name, chunk: Chunk::new() }
}

///|
impl Eq for Function with op_equal(self, other) {
  self.arity == other.arity && self.name == other.name
}

///|
priv struct NativeFunction {
  name : String
  arity : Int
  function : (Int, FixedArray[Value]) -> Value
}

///|
impl Eq for NativeFunction with op_equal(self, other) {
  self.arity == other.arity && self.name == other.name
}

///|
priv struct Closure {
  function : Function
  upvalues : FixedArray[Upval?]
  upvalue_count : Int
} derive(Eq)

///|
fn Closure::new(function : Function) -> Closure {
  let upvalue_count = function.upvalue_count
  let upvalues = FixedArray::makei(upvalue_count, fn(_i) { None })
  { function, upvalues, upvalue_count }
}

///|
priv struct Upval {
  mut location : Int
  mut next : Upval?
  mut closed : Value
} derive(Eq)

///|
priv struct Class {
  name : String
  methods : Map[String, Value]
} derive(Eq)

///|
fn Class::new(name : String) -> Class {
  { name, methods: {} }
}

///|
priv struct Instance {
  clazz : Class
  fields : Map[String, Value]
} derive(Eq)

///|
fn Instance::new(clazz : Class) -> Instance {
  { clazz, fields: {} }
}

///|
priv struct BoundMethod {
  receiver : Value
  mthd : Closure
} derive(Eq)

///|
fn BoundMethod::new(receiver : Value, mthd : Closure) -> BoundMethod {
  { receiver, mthd }
}

///|
enum Value {
  NilVal
  BoolVal(Bool)
  NumberVal(Double)
  StringVal(String)
  FunctionVal(Function)
  NativeFunctionVal(NativeFunction)
  ClosureVal(Closure)
  ClassVal(Class)
  InstanceVal(Instance)
  BoundMethodVal(BoundMethod)
} derive(Eq)

///|
fn is_falsey(self : Value) -> Bool {
  match self {
    NilVal => true
    BoolVal(b) => not(b)
    _ => false
  }
}

///|
pub impl Show for Value with output(self, logger) {
  match self {
    NilVal => logger.write_string("nil")
    BoolVal(b) => logger.write_object(b)
    NumberVal(n) => logger.write_object(n)
    StringVal(s) => logger.write_string(s)
    FunctionVal(f) => print_function(logger, f)
    NativeFunctionVal(f) => logger.write_string("<native fn \{f.name}>")
    ClosureVal(c) => print_function(logger, c.function)
    ClassVal(c) => logger.write_string(c.name)
    InstanceVal(i) => logger.write_string("\{i.clazz.name} instance")
    BoundMethodVal(m) => print_function(logger, m.mthd.function)
  }
}

///|
fn print_function(logger : &Logger, function : Function) -> Unit {
  if function.name != "" {
    logger.write_string("<fn \{function.name}>")
  } else {
    logger.write_string("<script>")
  }
}

///|
priv struct ValueArray {
  values : Array[Value]
} derive(Show)

///|
fn ValueArray::new() -> ValueArray {
  { values: [] }
}

///|
fn add_value(self : ValueArray, value : Value) -> Unit {
  self.values.push(value)
}
