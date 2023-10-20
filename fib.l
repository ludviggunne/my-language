
# - - - - - - FIBONACCI - - - - - - -

fn fib(n) = {
    
    if n < 2 {
        return n;
    } else {
        return fib(n - 1) + fib(n - 2);
    }
}

fn main() = {

    let n = 0;
    
    while n <= 10 {
        print fib(n);
        n += 1;
    }
}
