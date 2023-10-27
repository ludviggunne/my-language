
fn isPrime(n: int) = {

    let d: int = 2;

    while d < n / 2 {

        if n % d == 0 {
            return false;
        }

        d += 1;
    }

    return true;
}

fn main() = {

    let n: int = 2;

    while n < 100 {

        if isPrime(n) {
            print n;
        }

        n += 1;
    }

    return 0;
}
