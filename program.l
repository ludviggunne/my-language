
let number = 2;

# This is a comment
# This is another comment

while number <= 100000 {
    
    let y = -1;
    let prime = 1;
    let divisor = 3;

    if number % 2 == 0 {
        prime = 0;
    } else {
        
        while divisor < number / 2 {
            
            if number % divisor == 0 {
                
                prime = 0;
                break;
            }

            divisor += 2;
        }
    }

    if prime {
        print number;
    }

    number += 1;
}
