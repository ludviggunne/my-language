
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
Variables can be shadowed:
```
let x = 0;
{
    let x = 1;
    print x; # prints 1
}
print x; # prints 0
```

### Functions
```
fn isEven(n: int): bool = {
    return n % 2 == 0;
}
```
Return types may also be inferred (if the function is recursive, it must have a
return statement with a specified type **before** the first call to itself).
```
fn add(x: int, y: int) = { return x + y; } # return integer
```
All functions must return a value.
The `main` function is the entry point of the program.
It must return an integer and have no parameters.
The parameter count is limited to four.
A function must be declared before it is used.


The compiler verifies that a function always returns.
The following code does not compile:
```
fn function(x: bool) = {

    if x {
        return 3;
    }
}
```
but this does:
```
fn function(x: bool) = {

    if x {
        return 3;
    } else {
        return 2;
    }
}
```

### Control flow
```
if x == 70 {
    x -= 1;
}
```
Arithemtic and logical expressions are evaluated at compile time,
and `if`/`else` branches can be eliminated. The following code:
```
if 1 + 2 > 5 {
    print 4;
} else {
    print 3 * 5;
}
```
will be reduced to:
```
print 15;
```
There are also `while`, `break` and `continue` statements that
do what you'd expect.

### Printing to stdout
There is a special `print` statement that prints it's argument (bools are printed as 1/0).
```
print x + y;
```

## Formatting
The build script also builds a simple code formatter, which can be used like so:
```
cat program.l | ./lfmt > tmp && mv tmp program.l
```
