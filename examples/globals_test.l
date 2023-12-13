
let a = 2;
let b = a + 4;

fn addOne(x: int) = { return x + 1; };

let c = addOne(b);

fn main() = {
    a += 1;
    print a == 3;
    print b == 6;
    return 0;
};
