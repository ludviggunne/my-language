
# - - - - - - FIBONACCI - - - - - - -

fn fib(n: int): int = {
    
    if n < 2 {
        return n;
    } else {
        return fib(n - 1) + fib(n - 2);
    }
}

fn main(): int = {

    let n: int = 0;
    let c: bool = true;
    
    while c {
        print fib(n);
        n += 1;
        c = n <= 10;
    }
}
