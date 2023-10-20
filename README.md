
# Compiler
Compiler for my tiny language. Only compiles to **linux-x86_64**.  Only 64-bit
signed integers as variables, all functions (except main) must return an
integer.  Parameter count is limited to 4.

## Requirements
* Zig compiler
* gcc for assembling and linking (printf)
* Low expectations

## Usage
1. Write the program in **program.l**
2. Run make
3. Run **./program**

## Features
* Rudimentary type checking (bool/int)
* Variable shadowing
* Constant folding of compile time known arithmetic and logical expressions
* Eliminates if/else branches if condition is compile time known
