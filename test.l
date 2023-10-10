
let y = 10;
let x = 11;

let z = x * (3 + y);

x = x * y + 22;

if x > y {
    
    let tmp = x;
    x = y;
    y = tmp;
}

while y > x {

    x += 1;
    y = -2;
}

{
    block = this;
}
