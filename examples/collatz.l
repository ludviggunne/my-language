
fn iterate(n: int): int = {
    
    if n % 2 == 0 {
        return n / 2;
    } else {
        return 3 * n + 1;
    }
}

fn collatz(n: int): int = {
    
    while n > 1 {
        print n;
        n = iterate(n);
    }
    
    print n;

    return 0;
}

fn main(): int = {
    
    let n: int = 17;

    let _: int = collatz(n);
}
