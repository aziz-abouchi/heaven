# tree-sitter-pie

A tree-sitter grammar for the **pie** language from "The Little Typer" by Daniel P. Friedman and David Thrane Christiansen.

## About Pie

Pie is a dependently-typed programming language designed for teaching dependent types. It features:

- Dependent types with Pi (Π) and Sigma (Σ) types
- Natural numbers (Nat), atoms, pairs, lists, vectors, and more
- Lambda expressions and function application
- Type annotations with `the`
- Equality types and proofs

## Installation

```bash
npm install tree-sitter-pie
```

## Usage

### As a Tree-sitter Grammar

```javascript
const Parser = require('tree-sitter');
const Pie = require('tree-sitter-pie');

const parser = new Parser();
parser.setLanguage(Pie);

const sourceCode = `
(claim one Nat)
(define one (add1 zero))
`;

const tree = parser.parse(sourceCode);
console.log(tree.rootNode.toString());
```

### Testing

Run the test suite:

```bash
npm test
```

### Building

Generate the parser:

```bash
npm run build
```

## Language Features

The grammar supports:

### Top-level Forms
- `claim` - Declare a type for a name
- `define` - Define a value for a name
- `check-same` - Check that two expressions are the same

### Types
- `Nat` - Natural numbers
- `Atom` - Atomic symbols
- `U` - Universe of types
- `->` - Function types
- `Pi` (Π) - Dependent function types
- `Sigma` (Σ) - Dependent pair types
- `Pair` - Non-dependent pairs
- `List` - Lists
- `Vec` - Vectors (length-indexed lists)
- `Either` - Sum types
- `=` - Equality types
- `Trivial` - Unit type
- `Absurd` - Empty type

### Expressions
- Literals: numbers, quoted atoms
- Variables and symbols
- `lambda` (λ) - Anonymous functions
- `the` - Type annotations
- Function application
- Built-in operations: `add1`, `cons`, `car`, `cdr`, `head`, `tail`, etc.

### Comments
- Line comments: `;` 
- Block comments: `#| ... |#`

## Example

```scheme
; Define natural number type
(claim one Nat)
(define one (add1 zero))

(claim two Nat)
(define two (add1 one))

; Define addition function
(claim + (-> Nat Nat Nat))
(define +
  (lambda (n m)
    (iter-Nat n
      m
      (lambda (sum) (add1 sum)))))

; Check equality
(check-same Nat (+ one one) two)
```

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## License

MIT

## References

- [The Little Typer](https://mitpress.mit.edu/9780262536431/the-little-typer/) by Daniel P. Friedman and David Thrane Christiansen
- [Tree-sitter](https://tree-sitter.github.io/tree-sitter/)
