# Heaven Language Documentation

## Overview
Heaven is a functional programming language with pattern matching, built on top of the Heaven expression engine. It supports Peano arithmetic and recursive function definitions.

## Syntax

### Function Definition
function_name pattern1 pattern2 ... = body

Patterns can be:
- Variables: lowercase letters (e.g., n, m, x)
- Constructors: uppercase or mixed case (e.g., zero, succ)
- Compound patterns: (constructor pattern) (e.g., (succ n))

### Function Calls
function_name arg1 arg2 ...

Or with parentheses:
function_name(arg1, arg2, ...)

### Peano Arithmetic

Numbers:
- zero = 0
- succ zero = 1
- succ (succ zero) = 2
- etc.

Operations:
- add n m - addition
- mul n m - multiplication
- sub n m - subtraction
- div n m - integer division

## Examples

### Factorial
factorial zero = succ zero
factorial (succ n) = mul (succ n) (factorial n)

factorial (succ (succ (succ zero)))  # Returns 6

### Addition
add zero n = n
add (succ n) m = succ (add n m)

add (succ (succ zero)) (succ (succ (succ zero)))  # Returns 5

### Fibonacci
fib zero = zero
fib (succ zero) = succ zero
fib (succ (succ n)) = add (fib (succ n)) (fib n)

fib (succ (succ (succ (succ (succ zero)))))  # Returns 5

## REPL Commands

- help - Show help
- stats - Show statistics
- load <file> - Load a .hvn file
- quit - Exit the REPL

## Architecture

Heaven is built on:
- Expression Engine: Core evaluation and pattern matching
- Pattern Matching: Structural pattern matching with variable binding
- Peano Evaluation: Automatic conversion of Peano numbers to integers
- Recursive Substitution: Proper handling of recursive function calls

## Future Features

- Type system
- Module system
- More built-in functions
- Performance optimizations
- WebAssembly improvements
