; Highlight queries for pie language

; Comments
(comment) @comment

; Keywords
["claim" "define" "check-same" "the" "lambda" "λ" "quote"] @keyword

; Type keywords
["Pi" "Π" "Sigma" "Σ" "->"] @keyword.type

; Built-in types
[
  "Nat"
  "Atom"
  "U"
  "Trivial"
  "Absurd"
  "List"
  "Vec"
  "Either"
  "Pair"
  "="
] @type.builtin

; Built-in values
[
  "zero"
  "sole"
  "nil"
] @constant.builtin

; Built-in functions
[
  "add1"
  "cons"
  "car"
  "cdr"
  "head"
  "tail"
  "which-Nat"
  "iter-Nat"
  "rec-Nat"
  "ind-Nat"
  "rec-List"
  "ind-List"
  "vec-head"
  "vec-tail"
  "ind-Vec"
  "ind-Either"
  "ind-Absurd"
  "replace"
  "trans"
  "cong"
  "symm"
  "ind-="
] @function.builtin

; Numbers
(number) @number

; Strings
(string) @string

; Atoms
(atom_literal) @string.special

; Symbols
(symbol) @variable

; Function parameters in lambda/Pi/Sigma
(parenthesized_expr
  ["lambda" "λ"] 
  (symbol) @parameter)

(parenthesized_expr
  ["Pi" "Π" "Sigma" "Σ"]
  (symbol) @parameter)

; Punctuation
["(" ")"] @punctuation.bracket
