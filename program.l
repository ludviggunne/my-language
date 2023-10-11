
let number = 2;

while number <= 100 {
    
    let prime = 1;
    let divisor = 2;
    
    while divisor < number / 2 {
        
        if number % divisor == 0 {
            
            prime = 0;
            break;
        }

        divisor += 1;
    }

    if prime {
        print number;
    }

    number += 1;
}
