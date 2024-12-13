///|
struct Compiler {
  scanner : Scanner
  parse_state : ParseState
  chunk : Chunk
  rules : Map[TokenKind, ParseRule]
  debug : Bool
}

///|
fn Compiler::new(source : String, debug~ : Bool = false) -> Compiler {
  {
    scanner: Scanner::new(source),
    parse_state: ParseState::new(),
    chunk: Chunk::new(),
    rules: init_rules_table(),
    debug,
  }
}

///|
fn compile(self : Compiler) -> Result[Chunk, String] {
  self.parse_state.had_error = false
  self.parse_state.panic_mode = false
  self.advance()
  self.expression()
  self.consume(EOF, "Expect end of expression.")
  if self.parse_state.had_error {
    return Err("Compiler error")
  }
  self.emit_return()
  if self.debug {
    println(self.chunk.pprint("code"))
  }
  Ok(self.chunk)
}

//
// Parsing
//

///|
typealias Precedence = Int

///|
typealias ParseFn = (Compiler) -> Unit

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
const PREC_PRIMARY = 10

///|
struct ParseState {
  mut previous : Token
  mut current : Token
  mut had_error : Bool
  mut panic_mode : Bool
}

///|
fn ParseState::new() -> ParseState {
  let dummy = { kind: EOF, str: "", start: 0, length: 0, line: 1 }
  { previous: dummy, current: dummy, had_error: false, panic_mode: false }
}

///|
struct ParseRule {
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
  rules[LeftParen] = ParseRule::new(Some(grouping), None, PREC_NONE)
  rules[RightParen] = ParseRule::new(None, None, PREC_NONE)
  rules[LeftBrace] = ParseRule::new(None, None, PREC_NONE)
  rules[RightBrace] = ParseRule::new(None, None, PREC_NONE)
  rules[Comma] = ParseRule::new(None, None, PREC_NONE)
  rules[Dot] = ParseRule::new(None, None, PREC_NONE)
  rules[Minus] = ParseRule::new(Some(unary), Some(binary), PREC_TERM)
  rules[Plus] = ParseRule::new(None, Some(binary), PREC_TERM)
  rules[Semicolon] = ParseRule::new(None, None, PREC_NONE)
  rules[Slash] = ParseRule::new(None, Some(binary), PREC_FACTOR)
  rules[Star] = ParseRule::new(None, Some(binary), PREC_FACTOR)
  rules[Bang] = ParseRule::new(None, None, PREC_NONE)
  rules[BangEqual] = ParseRule::new(None, None, PREC_NONE)
  rules[Equal] = ParseRule::new(None, None, PREC_NONE)
  rules[EqualEqual] = ParseRule::new(None, None, PREC_NONE)
  rules[Greater] = ParseRule::new(None, None, PREC_NONE)
  rules[GreaterEqual] = ParseRule::new(None, None, PREC_NONE)
  rules[Less] = ParseRule::new(None, None, PREC_NONE)
  rules[LessEqual] = ParseRule::new(None, None, PREC_NONE)
  rules[Identifier] = ParseRule::new(None, None, PREC_NONE)
  rules[String] = ParseRule::new(None, None, PREC_NONE)
  rules[Number] = ParseRule::new(Some(num), None, PREC_NONE)
  rules[And] = ParseRule::new(None, None, PREC_NONE)
  rules[Class] = ParseRule::new(None, None, PREC_NONE)
  rules[Else] = ParseRule::new(None, None, PREC_NONE)
  rules[False] = ParseRule::new(None, None, PREC_NONE)
  rules[For] = ParseRule::new(None, None, PREC_NONE)
  rules[Fun] = ParseRule::new(None, None, PREC_NONE)
  rules[If] = ParseRule::new(None, None, PREC_NONE)
  rules[Nil] = ParseRule::new(None, None, PREC_NONE)
  rules[Or] = ParseRule::new(None, None, PREC_NONE)
  rules[Print] = ParseRule::new(None, None, PREC_NONE)
  rules[Return] = ParseRule::new(None, None, PREC_NONE)
  rules[Super] = ParseRule::new(None, None, PREC_NONE)
  rules[This] = ParseRule::new(None, None, PREC_NONE)
  rules[True] = ParseRule::new(None, None, PREC_NONE)
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
    self.rules[self.parse_state.previous.kind].unwrap().prefix {
    Some(f) => f
    None => {
      self.error("Expect expression.")
      return
    }
  }
  prefix_rule(self)
  while precedence <=
        self.rules[self.parse_state.current.kind].unwrap().precedence {
    self.advance()
    let infix_rule = self.rules[self.parse_state.previous.kind].unwrap().infix.unwrap()
    infix_rule(self)
  }
}

///|
fn expression(self : Compiler) -> Unit {
  self.parse_precedence(PREC_ASSIGNMENT)
}

///|
fn unary(self : Compiler) -> Unit {
  let operator = self.parse_state.previous.kind

  // Compile the operand
  self.parse_precedence(PREC_UNARY)

  // Emit instruction
  match operator {
    Minus => self.emit_byte(OP_NEGATE)
    _ => ()
  }
}

///|
fn binary(self : Compiler) -> Unit {
  let operator = self.parse_state.previous.kind
  let rule = self.rules[operator].unwrap()
  self.parse_precedence(rule.precedence + 1)
  match operator {
    Plus => self.emit_byte(OP_ADD)
    Minus => self.emit_byte(OP_SUBTRACT)
    Star => self.emit_byte(OP_MULTIPLY)
    Slash => self.emit_byte(OP_DIVIDE)
    _ => ()
  }
}

///|
fn num(self : Compiler) -> Unit {
  let value = try {
    @strconv.parse_double!(self.parse_state.previous.str)
  } catch {
    StrConvError(_) => {
      self.error("Invalid number.")
      return
    }
  }
  self.emit_constant(value)
}

///|
fn grouping(self : Compiler) -> Unit {
  self.expression()
  self.consume(RightParen, "Expect ')' after expression.")
}

///|
fn advance(self : Compiler) -> Unit {
  self.parse_state.previous = self.parse_state.current
  for {
    self.parse_state.current = self.scanner.scan()
    if self.parse_state.current.kind != Error {
      break
    }
    self.error_at_current(self.parse_state.current.str)
  }
}

///|
fn consume(self : Compiler, kind : TokenKind, message : String) -> Unit {
  if self.parse_state.current.kind == kind {
    self.advance()
  } else {
    self.error_at_current(message)
  }
}

///|
fn error_at_current(self : Compiler, message : String) -> Unit {
  self.error_at(self.parse_state.current, message)
}

///|
fn error(self : Compiler, message : String) -> Unit {
  self.error_at(self.parse_state.previous, message)
}

///|
fn error_at(self : Compiler, token : Token, message : String) -> Unit {
  if self.parse_state.panic_mode {
    return
  }
  self.parse_state.panic_mode = true
  self.parse_state.had_error = true
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

//
// Codegen
//

///|
const BYTE_MAX = 255

///|
fn emit_byte(self : Compiler, byte : Byte) -> Unit {
  self.chunk.write(byte, self.parse_state.previous.line)
}

///|
fn emit_bytes(self : Compiler, byte1 : Byte, byte2 : Byte) -> Unit {
  self.emit_byte(byte1)
  self.emit_byte(byte2)
}

///|
fn emit_return(self : Compiler) -> Unit {
  self.emit_byte(OP_RETURN)
}

///|
fn emit_constant(self : Compiler, value : Value) -> Unit {
  fn make_constant(value) {
    let constant = self.chunk.add_constant(value)
    if constant > BYTE_MAX {
      self.error("Too many constants in one chunk.")
      0
    } else {
      constant
    }
  }

  self.emit_bytes(OP_CONSTANT, make_constant(value).to_byte())
}
