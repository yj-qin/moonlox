///|
fn padding_prefix(num : Int, count : Int, content~ : String = " ") -> String {
  let mut n = num.to_string()
  let len = n.length()
  if len < count {
    for i in 0..<(count - len) {
      n = content + n
    }
  }
  n
}

///|
fn is_digit(c : Char?) -> Bool {
  if c == None {
    return false
  }
  let c = c.unwrap()
  '0' <= c && c <= '9'
}

///|
fn is_alpha(c : Char?) -> Bool {
  if c == None {
    return false
  }
  let c = c.unwrap()
  ('a' <= c && c <= 'z') || ('A' <= c && c <= 'Z') || c == '_'
}
