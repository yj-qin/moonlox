///|
const MAX_LOCAL_VAR_COUNT = 256

///|
const MAX_UPVALUE_COUNT = 256

///|
const MAX_JUMP = 65535

///|
priv struct CompileState {
  enclosing : CompileState?
  function : Function
  function_kind : FunctionKind
  locals : FixedArray[Local?]
  mut local_count : Int
  upvalues : FixedArray[Upvalue?]
  mut scope_depth : Int
} derive(Show)

///|
fn CompileState::new(
  function_kind : FunctionKind,
  function_name~ : String = "",
  enclosing~ : CompileState? = None
) -> CompileState {
  let locals = FixedArray::make(MAX_LOCAL_VAR_COUNT, None)
  let upvalues = FixedArray::make(MAX_UPVALUE_COUNT, None)
  locals[0] = Some({
    name: if function_kind != Function {
      Token::this()
    } else {
      Token::dummy()
    },
    depth: 0,
    is_captured: false,
  })
  {
    enclosing,
    function: Function::new(name=function_name),
    function_kind,
    locals,
    local_count: 1,
    upvalues,
    scope_depth: 0,
  }
}

///|
priv struct ClassCompileState {
  enclosing : ClassCompileState?
  mut has_super : Bool
}

///|
priv struct Compiler {
  scanner : Scanner
  parser : Parser
  mut current : CompileState
  mut current_class : ClassCompileState?
  rules : Map[TokenKind, ParseRule]
  debug : Bool
}

///|
priv struct Local {
  name : Token
  mut depth : Int
  mut is_captured : Bool
} derive(Show)

///|
priv struct Upvalue {
  index : Int
  is_local : Bool
} derive(Show)

///|
fn Compiler::new(source : String, debug~ : Bool = false) -> Compiler {
  {
    scanner: Scanner::new(source),
    parser: Parser::new(),
    current: CompileState::new(Script),
    current_class: None,
    rules: init_rules_table(),
    debug,
  }
}

///|
fn compile(self : Compiler) -> Result[Function, String] {
  self.parser.had_error = false
  self.parser.panic_mode = false
  self.advance()
  while not(self.consume(EOF)) {
    self.declaration()
  }
  if self.parser.had_error {
    return Err("Compiler error")
  }
  Ok(self.end_function())
}

///|
fn end_function(self : Compiler) -> Function {
  self.emit_return()
  let function = self.current.function
  if self.debug && not(self.parser.had_error) {
    println(
      self
      .current_chunk()
      .pprint(
        if self.current.function.name != "" {
          self.current.function.name
        } else {
          "<script>"
        },
      ),
    )
  }
  match self.current.enclosing {
    Some(enclosing) => self.current = enclosing
    None => ()
  }
  function
}

//
// Parsing
//

///|
typealias Int as Precedence 

///|
typealias (Compiler, Bool) -> Unit as ParseFn

///|
const PREC_NONE = 0

///|
const PREC_ASSIGNMENT = 1

///|
const PREC_OR = 2

///|
const PREC_AND = 3

///|
const PREC_EQUALITY = 4

///|
const PREC_COMPARISON = 5

///|
const PREC_TERM = 6

///|
const PREC_FACTOR = 7

///|
const PREC_UNARY = 8

///|
const PREC_CALL = 9

///|
//const PREC_PRIMARY = 10

///|
priv struct Parser {
  mut previous : Token
  mut current : Token
  mut had_error : Bool
  mut panic_mode : Bool
}

///|
fn Parser::new() -> Parser {
  let dummy = Token::dummy()
  { previous: dummy, current: dummy, had_error: false, panic_mode: false }
}

///|
priv struct ParseRule {
  prefix : ParseFn?
  infix : ParseFn?
  precedence : Precedence
}

///|
fn ParseRule::new(
  prefix : ParseFn?,
  infix : ParseFn?,
  precedence : Precedence
) -> ParseRule {
  { prefix, infix, precedence }
}

///|
fn init_rules_table() -> Map[TokenKind, ParseRule] {
  let rules = {}
  rules[LeftParen] = ParseRule::new(Some(Compiler::grouping), Some(Compiler::call), PREC_CALL)
  rules[RightParen] = ParseRule::new(None, None, PREC_NONE)
  rules[LeftBrace] = ParseRule::new(None, None, PREC_NONE)
  rules[RightBrace] = ParseRule::new(None, None, PREC_NONE)
  rules[Comma] = ParseRule::new(None, None, PREC_NONE)
  rules[Dot] = ParseRule::new(None, Some(Compiler::dot), PREC_CALL)
  rules[Minus] = ParseRule::new(Some(Compiler::unary), Some(Compiler::binary), PREC_TERM)
  rules[Plus] = ParseRule::new(None, Some(Compiler::binary), PREC_TERM)
  rules[Semicolon] = ParseRule::new(None, None, PREC_NONE)
  rules[Slash] = ParseRule::new(None, Some(Compiler::binary), PREC_FACTOR)
  rules[Star] = ParseRule::new(None, Some(Compiler::binary), PREC_FACTOR)
  rules[Percent] = ParseRule::new(None, Some(Compiler::binary), PREC_FACTOR)
  rules[Bang] = ParseRule::new(Some(Compiler::unary), None, PREC_NONE)
  rules[BangEqual] = ParseRule::new(None, Some(Compiler::binary), PREC_EQUALITY)
  rules[Equal] = ParseRule::new(None, None, PREC_NONE)
  rules[EqualEqual] = ParseRule::new(None, Some(Compiler::binary), PREC_EQUALITY)
  rules[Greater] = ParseRule::new(None, Some(Compiler::binary), PREC_COMPARISON)
  rules[GreaterEqual] = ParseRule::new(None, Some(Compiler::binary), PREC_COMPARISON)
  rules[Less] = ParseRule::new(None, Some(Compiler::binary), PREC_COMPARISON)
  rules[LessEqual] = ParseRule::new(None, Some(Compiler::binary), PREC_COMPARISON)
  rules[Identifier] = ParseRule::new(Some(Compiler::variable), None, PREC_NONE)
  rules[String] = ParseRule::new(Some(Compiler::string), None, PREC_NONE)
  rules[Number] = ParseRule::new(Some(Compiler::number), None, PREC_NONE)
  rules[And] = ParseRule::new(None, Some(Compiler::and_), PREC_AND)
  rules[Class] = ParseRule::new(None, None, PREC_NONE)
  rules[Else] = ParseRule::new(None, None, PREC_NONE)
  rules[False] = ParseRule::new(Some(Compiler::literal), None, PREC_NONE)
  rules[For] = ParseRule::new(None, None, PREC_NONE)
  rules[Fun] = ParseRule::new(None, None, PREC_NONE)
  rules[If] = ParseRule::new(None, None, PREC_NONE)
  rules[Nil] = ParseRule::new(Some(Compiler::literal), None, PREC_NONE)
  rules[Or] = ParseRule::new(None, Some(Compiler::or), PREC_OR)
  rules[Print] = ParseRule::new(None, None, PREC_NONE)
  rules[Return] = ParseRule::new(None, None, PREC_NONE)
  rules[Super] = ParseRule::new(Some(Compiler::super_), None, PREC_NONE)
  rules[This] = ParseRule::new(Some(Compiler::this_), None, PREC_NONE)
  rules[True] = ParseRule::new(Some(Compiler::literal), None, PREC_NONE)
  rules[Var] = ParseRule::new(None, None, PREC_NONE)
  rules[While] = ParseRule::new(None, None, PREC_NONE)
  rules[Error] = ParseRule::new(None, None, PREC_NONE)
  rules[EOF] = ParseRule::new(None, None, PREC_NONE)
  rules
}

///|
fn parse_precedence(self : Compiler, precedence : Precedence) -> Unit {
  self.advance()
  let prefix_rule = match
    self.rules.get(self.parser.previous.kind).unwrap().prefix {
    Some(f) => f
    None => {
      self.error("Expect expression.")
      return
    }
  }
  let can_assign = precedence <= PREC_ASSIGNMENT
  prefix_rule(self, can_assign)
  while precedence <= self.rules.get(self.parser.current.kind).unwrap().precedence {
    self.advance()
    let infix_rule = self.rules.get(self.parser.previous.kind).unwrap().infix.unwrap()
    infix_rule(self, can_assign)
  }
  if can_assign && self.consume(Equal) {
    self.error("Invalid assignment target.")
  }
}

///|
fn parse_variable(self : Compiler, message : String) -> Int {
  self.assert_token(Identifier, message)
  self.declare_variable()
  if self.current.scope_depth > 0 {
    return 0
  }
  self.current_chunk().add_constant(StringVal(self.parser.previous.str))
}

///|
fn declare_variable(self : Compiler) -> Unit {
  if self.current.scope_depth == 0 {
    return
  }
  let name = self.parser.previous
  // Checks duplicate declaration in the same scope.
  for i = self.current.local_count - 1; i >= 0; i = i - 1 {
    let locl = self.current.locals[i].unwrap()
    if locl.depth != -1 && locl.depth < self.current.scope_depth {
      break
    }
    if identifier_equal(name, locl.name) {
      self.error("Already a variable with this name in this scope.")
    }
  }
  self.add_local(name)
}

///|
fn add_local(self : Compiler, name : Token) -> Unit {
  if self.current.local_count >= MAX_LOCAL_VAR_COUNT {
    self.error("Too many local variables in function.")
    return
  }
  self.current.locals[self.current.local_count] = Some({
    name,
    depth: -1,
    is_captured: false,
  })
  self.current.local_count += 1
}

///|
fn define_variable(self : Compiler, global : Int) -> Unit {
  if self.current.scope_depth > 0 {
    self.mark_initialized()
    return
  }
  self.emit_bytes(OP_DEFINE_GLOBAL, global.to_byte())
}

///|
fn mark_initialized(self : Compiler) -> Unit {
  if self.current.scope_depth == 0 {
    return
  }
  self.current.locals[self.current.local_count - 1].unwrap().depth = self.current.scope_depth
}

///|
fn expression(self : Compiler) -> Unit {
  self.parse_precedence(PREC_ASSIGNMENT)
}

///|
fn block(self : Compiler) -> Unit {
  while not(self.check(RightBrace)) && not(self.check(EOF)) {
    self.declaration()
  }
  self.assert_token(RightBrace, "Expect '}' after block.")
}

///|
fn declaration(self : Compiler) -> Unit {
  if self.consume(Class) {
    self.class_declaration()
  } else if self.consume(Fun) {
    self.fun_declaration()
  } else if self.consume(Var) {
    self.var_declaration()
  } else {
    self.statement()
  }
  if self.parser.panic_mode {
    self.synchronize()
  }
}

///|
fn var_declaration(self : Compiler) -> Unit {
  let global = self.parse_variable("Expect variable name.")
  if self.consume(Equal) {
    self.expression()
  } else {
    self.emit_byte(OP_NIL)
  }
  self.assert_token(Semicolon, "Expect ';' after variable declaration.")
  self.define_variable(global)
}

///|
fn fun_declaration(self : Compiler) -> Unit {
  let global = self.parse_variable("Expect function name.")
  self.mark_initialized()
  self.function(Function)
  self.define_variable(global)
}

///|
fn function(self : Compiler, function_kind : FunctionKind) -> Unit {
  let state = CompileState::new(
    function_kind,
    function_name=self.parser.previous.str,
    enclosing=Some(self.current),
  )
  self.current = state
  self.begin_scope()
  self.assert_token(LeftParen, "Expect '(' after function name.")
  if not(self.check(RightParen)) {
    for {
      self.current.function.arity += 1
      if self.current.function.arity > 255 {
        self.error_at_current("Can't have more than 255 parameters.")
      }
      let constant = self.parse_variable("Expect parameter name.")
      self.define_variable(constant)
      if not(self.consume(Comma)) {
        break
      }
    }
  }
  self.assert_token(RightParen, "Expect ')' after parameters.")
  self.assert_token(LeftBrace, "Expect '{' before function body.")
  self.block()
  let function = self.end_function()
  self.emit_bytes(
    OP_CLOSURE,
    self.make_constant(FunctionVal(function)).to_byte(),
  )
  for i = 0; i < function.upvalue_count; i = i + 1 {
    let upvalue = state.upvalues[i].unwrap()
    self.emit_byte(if upvalue.is_local { 1 } else { 0 })
    self.emit_byte(upvalue.index.to_byte())
  }
}

///|
fn class_declaration(self : Compiler) -> Unit {
  self.assert_token(Identifier, "Expect class name.")
  let class_name = self.parser.previous
  let name_constant = self.make_constant(StringVal(self.parser.previous.str))
  self.declare_variable()
  self.emit_bytes(OP_CLASS, name_constant.to_byte())
  self.define_variable(name_constant)
  let class_state = { enclosing: self.current_class, has_super: false }
  self.current_class = Some(class_state)
  // class inheritance
  if self.consume(Less) {
    self.assert_token(Identifier, "Expect superclass name.")
    self.variable(false)
    if identifier_equal(class_name, self.parser.previous) {
      self.error("A class can't inherit from itself.")
    }
    self.begin_scope()
    self.add_local(Token::synthetic("super"))
    self.define_variable(0)
    self.named_variable(class_name, false)
    self.emit_byte(OP_INHERIT)
    class_state.has_super = true
  }
  // load class for method binding
  self.named_variable(class_name, false)
  self.assert_token(LeftBrace, "Expect '{' before class body.")
  while not(self.check(RightBrace)) && not(self.check(EOF)) {
    self.mthd()
  }
  self.assert_token(RightBrace, "Expect '}' after class body.")
  // pop class
  self.emit_byte(OP_POP)
  if class_state.has_super {
    self.end_scope()
  }
  self.current_class = self.current_class.unwrap().enclosing
}

///|
fn mthd(self : Compiler) -> Unit {
  self.assert_token(Identifier, "Expect method name.")
  let constant = self.make_constant(StringVal(self.parser.previous.str))
  let kind = if self.parser.previous.str == "init" {
    Initializer
  } else {
    Method
  }
  self.function(kind)
  self.emit_bytes(OP_METHOD, constant.to_byte())
}

///|
fn statement(self : Compiler) -> Unit {
  if self.consume(Print) {
    self.print_statement()
  } else if self.consume(For) {
    self.for_statement()
  } else if self.consume(If) {
    self.if_statement()
  } else if self.consume(Return) {
    self.return_statement()
  } else if self.consume(While) {
    self.while_statement()
  } else if self.consume(LeftBrace) {
    self.begin_scope()
    self.block()
    self.end_scope()
  } else {
    self.expression_statement()
  }
}

///|
fn expression_statement(self : Compiler) -> Unit {
  self.expression()
  self.assert_token(Semicolon, "Expect ';' after expression.")
  self.emit_byte(OP_POP)
}

///|
fn return_statement(self : Compiler) -> Unit {
  if self.current.function_kind == Script {
    self.error("Can't return from top-level code.")
  }
  if self.consume(Semicolon) {
    self.emit_return()
  } else {
    if self.current.function_kind == Initializer {
      self.error("Can't return a value from an initializer.")
    }
    self.expression()
    self.assert_token(Semicolon, "Expect ';' after return value.")
    self.emit_byte(OP_RETURN)
  }
}

///|
fn if_statement(self : Compiler) -> Unit {
  self.assert_token(LeftParen, "Expect '(' after 'if'.")
  self.expression()
  self.assert_token(RightParen, "Expect ')' after condition.")
  let then_jump = self.emit_jump(OP_JUMP_IF_FALSE)
  self.emit_byte(OP_POP)
  self.statement()
  let else_jump = self.emit_jump(OP_JUMP)
  self.patch_jump(then_jump)
  self.emit_byte(OP_POP)
  if self.consume(Else) {
    self.statement()
  }
  self.patch_jump(else_jump)
}

///|
fn while_statement(self : Compiler) -> Unit {
  let loop_start = self.current_chunk().count
  self.assert_token(LeftParen, "Expect '(' after 'while'.")
  self.expression()
  self.assert_token(RightParen, "Expect ')' after condition.")
  let exit_jump = self.emit_jump(OP_JUMP_IF_FALSE)
  self.emit_byte(OP_POP)
  self.statement()
  self.emit_loop(loop_start)
  self.patch_jump(exit_jump)
  self.emit_byte(OP_POP)
}

///|
fn for_statement(self : Compiler) -> Unit {
  self.begin_scope()
  self.assert_token(LeftParen, "Expect '(' after 'for'.")
  // Initializer clause
  if self.consume(Semicolon) {
    // No initializer.
  } else if self.consume(Var) {
    self.var_declaration()
  } else {
    self.expression_statement()
  }
  let mut loop_start = self.current_chunk().count
  // Condition clause
  let mut exit_jump = -1
  if not(self.consume(Semicolon)) {
    self.expression()
    self.assert_token(Semicolon, "Expect ';' after loop condition.")

    // Jump out of the loop if the condition is false
    exit_jump = self.emit_jump(OP_JUMP_IF_FALSE)
    self.emit_byte(OP_POP)
  }
  // Increment clause
  if not(self.consume(RightParen)) {
    let body_jump = self.emit_jump(OP_JUMP)
    let increment_start = self.current_chunk().count
    self.expression()
    self.emit_byte(OP_POP)
    self.assert_token(RightParen, "Expect ')' after for clauses.")
    self.emit_loop(loop_start)
    loop_start = increment_start
    self.patch_jump(body_jump)
  }
  self.statement()
  self.emit_loop(loop_start)
  if exit_jump != -1 {
    self.patch_jump(exit_jump)
    self.emit_byte(OP_POP)
  }
  self.end_scope()
}

///|
fn print_statement(self : Compiler) -> Unit {
  self.expression()
  self.assert_token(Semicolon, "Expect ';' after value.")
  self.emit_byte(OP_PRINT)
}

///|
fn unary(self : Compiler, _can_assign : Bool) -> Unit {
  let operator = self.parser.previous.kind

  // Compile the operand
  self.parse_precedence(PREC_UNARY)

  // Emit instruction
  match operator {
    Bang => self.emit_byte(OP_NOT)
    Minus => self.emit_byte(OP_NEGATE)
    _ => ()
  }
}

///|
fn binary(self : Compiler, _can_assign : Bool) -> Unit {
  let operator = self.parser.previous.kind
  let rule = self.rules.get(operator).unwrap()
  self.parse_precedence(rule.precedence + 1)
  match operator {
    BangEqual => self.emit_bytes(OP_EQUAL, OP_NOT)
    EqualEqual => self.emit_byte(OP_EQUAL)
    Greater => self.emit_byte(OP_GREATER)
    GreaterEqual => self.emit_bytes(OP_LESS, OP_NOT)
    Less => self.emit_byte(OP_LESS)
    LessEqual => self.emit_bytes(OP_GREATER, OP_NOT)
    Plus => self.emit_byte(OP_ADD)
    Minus => self.emit_byte(OP_SUBTRACT)
    Star => self.emit_byte(OP_MULTIPLY)
    Slash => self.emit_byte(OP_DIVIDE)
    Percent => self.emit_byte(OP_MOD)
    _ => ()
  }
}

///|
fn call(self : Compiler, _can_assign : Bool) -> Unit {
  let arg_count = self.argument_list()
  self.emit_bytes(OP_CALL, arg_count.to_byte())
}

///|
fn dot(self : Compiler, can_assign : Bool) -> Unit {
  self.assert_token(Identifier, "Expect property name after '.'.")
  let name = self.make_constant(StringVal(self.parser.previous.str))
  if can_assign && self.consume(Equal) {
    self.expression()
    self.emit_bytes(OP_SET_PROPERTY, name.to_byte())
  } else if self.consume(LeftParen) {
    let arg_count = self.argument_list()
    self.emit_bytes(OP_INVOKE, name.to_byte())
    self.emit_byte(arg_count.to_byte())
  } else {
    self.emit_bytes(OP_GET_PROPERTY, name.to_byte())
  }
}

///|
fn argument_list(self : Compiler) -> Int {
  let mut arg_count = 0
  if not(self.check(RightParen)) {
    for {
      self.expression()
      if arg_count == 255 {
        self.error("Can't have more than 255 arguments.")
      }
      arg_count += 1
      if not(self.consume(Comma)) {
        break
      }
    }
  }
  self.assert_token(RightParen, "Expect ')' after arguments.")
  arg_count
}

///|
fn literal(self : Compiler, _can_assign : Bool) -> Unit {
  match self.parser.previous.kind {
    False => self.emit_byte(OP_FALSE)
    True => self.emit_byte(OP_TRUE)
    Nil => self.emit_byte(OP_NIL)
    _ => ()
  }
}

///|
fn number(self : Compiler, _can_assign : Bool) -> Unit {
  let value = try {
    @strconv.parse_double(self.parser.previous.str)
  } catch {
    StrConvError(_) => {
      self.error("Invalid number.")
      return
    }
  }
  self.emit_constant(NumberVal(value))
}

///|
fn string(self : Compiler, _can_assign : Bool) -> Unit {
  self.emit_constant(StringVal(self.parser.previous.str))
}

///|
fn variable(self : Compiler, can_assign : Bool) -> Unit {
  self.named_variable(self.parser.previous, can_assign)
}

///|
fn this_(self : Compiler, _can_assign : Bool) -> Unit {
  if self.current_class.is_empty() {
    self.error("Can't use 'this' outside of a class.")
    return
  }
  self.variable(false)
}

///|
fn super_(self : Compiler, _can_assign : Bool) -> Unit {
  if self.current_class.is_empty() {
    self.error("Can't use 'super' outside of a class.")
  } else if not(self.current_class.unwrap().has_super) {
    self.error("Can't use 'super' in a class with no superclass.")
  }
  self.assert_token(Dot, "Expect '.' after 'super'.")
  self.assert_token(Identifier, "Expect superclass method name.")
  let name = self.make_constant(StringVal(self.parser.previous.str))
  self.named_variable(Token::synthetic("this"), false)
  if self.consume(LeftParen) {
    let arg_count = self.argument_list()
    self.named_variable(Token::synthetic("super"), false)
    self.emit_bytes(OP_SUPER_INVOKE, name.to_byte())
    self.emit_byte(arg_count.to_byte())
  } else {
    self.named_variable(Token::synthetic("super"), false)
    self.emit_bytes(OP_GET_SUPER, name.to_byte())
  }
}

///|
fn named_variable(self : Compiler, name : Token, can_assign : Bool) -> Unit {
  let mut arg = self.resolve_local(self.current, name)
  let mut get_op = OP_NOP
  let mut set_op = OP_NOP
  if arg != -1 {
    get_op = OP_GET_LOCAL
    set_op = OP_SET_LOCAL
  } else {
    arg = self.resolve_upvalue(self.current, name)
    if arg != -1 {
      get_op = OP_GET_UPVALUE
      set_op = OP_SET_UPVALUE
    } else {
      arg = self.current_chunk().add_constant(StringVal(name.str))
      get_op = OP_GET_GLOBAL
      set_op = OP_SET_GLOBAL
    }
  }
  if can_assign && self.consume(Equal) {
    self.expression()
    self.emit_bytes(set_op, arg.to_byte())
  } else {
    self.emit_bytes(get_op, arg.to_byte())
  }
}

///|
fn grouping(self : Compiler, _can_assign : Bool) -> Unit {
  self.expression()
  self.assert_token(RightParen, "Expect ')' after expression.")
}

///|
fn and_(self : Compiler, _can_assign : Bool) -> Unit {
  let end_jump = self.emit_jump(OP_JUMP_IF_FALSE)
  self.emit_byte(OP_POP)
  self.parse_precedence(PREC_AND)
  self.patch_jump(end_jump)
}

///|
fn or(self : Compiler, _can_assign : Bool) -> Unit {
  let else_jump = self.emit_jump(OP_JUMP_IF_FALSE)
  let end_jump = self.emit_jump(OP_JUMP)
  self.patch_jump(else_jump)
  self.emit_byte(OP_POP)
  self.parse_precedence(PREC_OR)
  self.patch_jump(end_jump)
}

///|
fn begin_scope(self : Compiler) -> Unit {
  self.current.scope_depth += 1
}

///|
fn end_scope(self : Compiler) -> Unit {
  let state = self.current
  state.scope_depth -= 1
  // Pop out-of-scope local variables
  while state.local_count > 0 &&
        state.locals[state.local_count - 1].unwrap().depth > state.scope_depth {
    if state.locals[state.local_count - 1].unwrap().is_captured {
      self.emit_byte(OP_CLOSE_UPVALUE)
    } else {
      self.emit_byte(OP_POP)
    }
    state.local_count -= 1
  }
}

///|
fn Compiler::advance(self : Compiler) -> Unit {
  self.parser.previous = self.parser.current
  for {
    self.parser.current = self.scanner.scan()
    if self.parser.current.kind != Error {
      break
    }
    self.error_at_current(self.parser.current.str)
  }
}

///|
fn check(self : Compiler, kind : TokenKind) -> Bool {
  self.parser.current.kind == kind
}

///|
fn assert_token(self : Compiler, kind : TokenKind, message : String) -> Unit {
  if self.parser.current.kind == kind {
    self.advance()
  } else {
    self.error_at_current(message)
  }
}

///|
fn consume(self : Compiler, kind : TokenKind) -> Bool {
  if self.parser.current.kind != kind {
    false
  } else {
    self.advance()
    true
  }
}

///|
fn error_at_current(self : Compiler, message : String) -> Unit {
  self.error_at(self.parser.current, message)
}

///|
fn error(self : Compiler, message : String) -> Unit {
  self.error_at(self.parser.previous, message)
}

///|
fn error_at(self : Compiler, token : Token, message : String) -> Unit {
  if self.parser.panic_mode {
    return
  }
  self.parser.panic_mode = true
  self.parser.had_error = true
  let buf = StringBuilder::new()
  buf.write_string("[line \{token.line}] Error")
  match token.kind {
    Error => ()
    EOF => buf.write_string(" at end")
    _ => buf.write_string(" at \{token.str}")
  }
  buf.write_string(": \{message}")
  println(buf)
}

///|
fn identifier_equal(a : Token, b : Token) -> Bool {
  if a.length != b.length {
    false
  } else {
    a.str == b.str
  }
}

///|
fn resolve_local(self : Compiler, state : CompileState, name : Token) -> Int {
  for i = state.local_count - 1; i >= 0; i = i - 1 {
    let locl = state.locals[i].unwrap()
    if identifier_equal(name, locl.name) {
      if locl.depth == -1 {
        self.error("Can't read local variable in its own initializer.")
      }
      return i
    }
  }
  -1
}

///|
fn resolve_upvalue(self : Compiler, state : CompileState, name : Token) -> Int {
  if state.enclosing.is_empty() {
    return -1
  }
  let enclosing = state.enclosing.unwrap()
  let locl = self.resolve_local(enclosing, name)
  if locl != -1 {
    enclosing.locals[locl].unwrap().is_captured = true
    return self.add_upvalue(locl, true)
  }
  let upvalue = self.resolve_upvalue(enclosing, name)
  if upvalue != -1 {
    return self.add_upvalue(upvalue, false)
  }
  -1
}

///|
fn add_upvalue(self : Compiler, index : Int, is_local : Bool) -> Int {
  let upvalue_count = self.current.function.upvalue_count
  for i = 0; i < upvalue_count; i = i + 1 {
    let upvalue = self.current.upvalues[i].unwrap()
    if upvalue.index == index && upvalue.is_local == is_local {
      return i
    }
  }
  if upvalue_count == MAX_UPVALUE_COUNT {
    self.error("Too many closure variables in function.")
    return 0
  }
  self.current.upvalues[upvalue_count] = Some({ index, is_local })
  self.current.function.upvalue_count += 1
  upvalue_count
}

///|
fn synchronize(self : Compiler) -> Unit {
  self.parser.panic_mode = false
  while self.parser.current.kind != EOF {
    if self.parser.previous.kind == Semicolon {
      return
    }
    match self.parser.current.kind {
      Class | Fun | Var | For | If | While | Print | Return => return
      _ => ()
    }
    self.advance()
  }
}

//
// Codegen
//

///|
const BYTE_MAX = 255

///|
fn emit_byte(self : Compiler, byte : Byte) -> Unit {
  self.current_chunk().write(byte, self.parser.previous.line)
}

///|
fn emit_bytes(self : Compiler, byte1 : Byte, byte2 : Byte) -> Unit {
  self.emit_byte(byte1)
  self.emit_byte(byte2)
}

///|
fn emit_return(self : Compiler) -> Unit {
  if self.current.function_kind == Initializer {
    self.emit_bytes(OP_GET_LOCAL, 0)
  } else {
    self.emit_byte(OP_NIL)
  }
  self.emit_byte(OP_RETURN)
}

///|
fn emit_constant(self : Compiler, value : Value) -> Unit {
  self.emit_bytes(OP_CONSTANT, self.make_constant(value).to_byte())
}

///|
fn make_constant(self : Compiler, value : Value) -> Int {
  let constant = self.current_chunk().add_constant(value)
  if constant > BYTE_MAX {
    self.error("Too many constants in one chunk.")
    0
  } else {
    constant
  }
}

///|
fn emit_jump(self : Compiler, instruction : Byte) -> Int {
  self.emit_byte(instruction)
  self.emit_byte(0xff)
  self.emit_byte(0xff)
  self.current_chunk().count - 2
}

///|
fn patch_jump(self : Compiler, offset : Int) -> Unit {
  let jump = self.current_chunk().count - offset - 2
  if jump > MAX_JUMP {
    self.error("Too much code to jump over.")
  }
  self.current_chunk().code[offset] = (jump >> 8).to_byte() & 0xff
  self.current_chunk().code[offset + 1] = jump.to_byte() & 0xff
}

///|
fn emit_loop(self : Compiler, loop_start : Int) -> Unit {
  self.emit_byte(OP_LOOP)
  let offset = self.current_chunk().count - loop_start + 2
  if offset > MAX_JUMP {
    self.error("Loop body too large.")
  }
  self.emit_byte((offset >> 8).to_byte() & 0xff)
  self.emit_byte(offset.to_byte() & 0xff)
}

//
// Helper
//

///|
fn current_chunk(self : Compiler) -> Chunk {
  self.current.function.chunk
}
