
let a = 1;
let b = 1;

let i = 5;

while (i > 0) {

    let c = a + b;
    print c;
    b = a;
    a = c;
    i = i - 1;
}

print i;
