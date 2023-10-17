
fn fib(n) = {

    if n < 2 {
        return n;
    } else {
        return fib(n-1) + fib(n-2);
    }
}

fn main() = {

    let x = 10;
    while x > 0 {
        print fib(x);
    }
}
