
# Compiler
Compiler for my tiny language. Only compiles to **linux-x86_64**.

## Requirements
* Zig compiler
* gcc for assembling and linking (printf)
* Low expectations

## Building
Run `zig build`

## Usage
`./lc source.l -o program`

## Options
* **-d**: Print lexer output, AST & symbol table
* **-s**: Save assembly output (asm.S)

## Basics
### Variable declarations
The only currently supported types are 64-bit signed integers and booleans
(which are also 64-bit...)
```
let x: int = 69;
let nice: bool = true;
```
Types of variables may also be inferred:
```
let x = 0;    # integer
let y = true; # boolean
```

### Functions
```
fn isEven(n: int): bool = {
    return n % 2 == 0;
}
```
Return types may also be inferred:
```
fn add(x: int, y: int) = { return x + y; } # return integer
```
All functions must return a value.
The `main` function is the entry point of the program.
It must return an integer.
The parameter count is limited to four.

### Control flow
```
if x == 70 {
    x -= 1;
}
```

### Printing to stdout
There is a specific `print` statement that prints it's argument (bools are printed as 1/0).
```
print x + y;
```

## Formatting
The build script also builds a simple code formatter, which can be used like so:
```
cat program.l | ./lfmt > tmp && mv tmp program.l
```

## Compiler features
* Rudimentary type checking (bool/int)
* Variable shadowing
* Constant folding of compile time known arithmetic and logical expressions
* Eliminates if/else branches if condition is compile time known
