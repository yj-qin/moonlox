///|
enum TokenKind {
  // Single-character tokens
  LeftParen
  RightParen
  LeftBrace
  RightBrace
  Comma
  Dot
  Minus
  Plus
  Semicolon
  Slash
  Star
  Percent
  // One or two character tokens
  Bang
  BangEqual
  Equal
  EqualEqual
  Greater
  GreaterEqual
  Less
  LessEqual
  // Literals
  Identifier
  String
  Number
  // Keywords
  And
  Class
  Else
  False
  For
  Fun
  If
  Nil
  Or
  Print
  Return
  Super
  This
  True
  Var
  While
  // Others
  Error
  EOF
} derive(Eq, Hash, Show)

///|
struct Token {
  kind : TokenKind
  str : String
  start : Int
  length : Int
  line : Int
} derive(Show, Eq)

///|
fn Token::dummy() -> Token {
  { kind: EOF, str: "", start: 0, length: 0, line: 0 }
}

///|
fn Token::this() -> Token {
  { kind: This, str: "this", start: 0, length: 4, line: 0 }
}

///|
fn Token::synthetic(str : String) -> Token {
  { kind: Nil, str, start: 0, length: str.length(), line: 0 }
}

///|
let keywords : Map[String, TokenKind] = {
  "and": And,
  "class": Class,
  "else": Else,
  "false": False,
  "for": For,
  "fun": Fun,
  "if": If,
  "nil": Nil,
  "or": Or,
  "print": Print,
  "return": Return,
  "super": Super,
  "this": This,
  "true": True,
  "var": Var,
  "while": While,
}

///|
struct Scanner {
  source : String
  mut start : Int
  mut cur : Int
  mut line : Int
}

///|
fn Scanner::new(source : String) -> Scanner {
  { source, start: 0, cur: 0, line: 1 }
}

///|
fn scan(self : Scanner) -> Token {
  self.skip_whitespace()
  self.start = self.cur
  if self.is_at_end() {
    return self.make_token(EOF)
  }
  let c = self.advance()
  if is_alpha(Some(c)) {
    return self.identifier()
  }
  if is_digit(Some(c)) {
    return self.num()
  }
  match c {
    '(' => self.make_token(LeftParen)
    ')' => self.make_token(RightParen)
    '{' => self.make_token(LeftBrace)
    '}' => self.make_token(RightBrace)
    ';' => self.make_token(Semicolon)
    ',' => self.make_token(Comma)
    '.' => self.make_token(Dot)
    '+' => self.make_token(Plus)
    '-' => self.make_token(Minus)
    '*' => self.make_token(Star)
    '/' => self.make_token(Slash)
    '%' => self.make_token(Percent)
    '!' => self.make_token(if self.eat('=') { BangEqual } else { Bang })
    '=' => self.make_token(if self.eat('=') { EqualEqual } else { Equal })
    '<' => self.make_token(if self.eat('=') { LessEqual } else { Less })
    '>' => self.make_token(if self.eat('=') { GreaterEqual } else { Greater })
    '"' => self.str()
    _ => self.error_token("Unexpected character.")
  }
}

///|
fn Scanner::peek(self : Scanner) -> Char? {
  if self.is_at_end() {
    None
  } else {
    Some(self.source[self.cur])
  }
}

///|
fn peek_next(self : Scanner) -> Char? {
  if self.is_at_end() {
    None
  } else {
    Some(self.source[self.cur + 1])
  }
}

///|
fn advance(self : Scanner) -> Char {
  self.cur += 1
  self.source[self.cur - 1]
}

///|
fn eat(self : Scanner, expected : Char) -> Bool {
  if self.is_at_end() {
    false
  } else if self.peek() != Some(expected) {
    false
  } else {
    self.cur += 1
    true
  }
}

///|
fn is_at_end(self : Scanner) -> Bool {
  self.cur >= self.source.length()
}

///|
fn skip_whitespace(self : Scanner) -> Unit {
  for {
    match self.peek() {
      Some(' ' | '\r' | '\t') => self.cur += 1
      Some('\n') => {
        self.line += 1
        self.cur += 1
      }
      Some('/') =>
        match self.peek_next() {
          Some('/') =>
            // A comment goes until the end of the line.
            while self.peek() != Some('\n') && not(self.is_at_end()) {
              self.cur += 1
            }
          _ => return
        }
      _ => return
    }
  }
}

///|
fn str(self : Scanner) -> Token {
  while self.peek() != Some('"') && not(self.is_at_end()) {
    if self.peek() == Some('\n') {
      self.line += 1
    }
    self.cur += 1
  }
  if self.is_at_end() {
    return self.error_token("Unterminated string.")
  }

  // Closing quote
  self.cur += 1
  self.make_token(String)
}

///|
fn num(self : Scanner) -> Token {
  while is_digit(self.peek()) {
    self.cur += 1
  }
  if self.peek() == Some('.') {
    if is_digit(self.peek_next()) {
      self.cur += 1
      while is_digit(self.peek()) {
        self.cur += 1
      }
    }
  }
  self.make_token(Number)
}

///|
fn identifier(self : Scanner) -> Token {
  while is_alpha(self.peek()) || is_digit(self.peek()) {
    self.cur += 1
  }
  self.make_token(self.identifier_type())
}

///|
fn identifier_type(self : Scanner) -> TokenKind {
  let str = self.source.substring(start=self.start, end=self.cur)
  keywords.get_or_default(str, Identifier)
}

///|
fn make_token(self : Scanner, kind : TokenKind) -> Token {
  let str = if kind == String {
    self.source.substring(start=self.start + 1, end=self.cur - 1)
  } else {
    self.source.substring(start=self.start, end=self.cur)
  }
  {
    kind,
    str,
    start: self.start,
    length: self.cur - self.start,
    line: self.line,
  }
}

///|
fn error_token(self : Scanner, message : String) -> Token {
  {
    kind: Error,
    str: message,
    start: self.start,
    length: self.cur - self.start,
    line: self.line,
  }
}
