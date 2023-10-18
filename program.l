
# - - - - - - FIBONACCI - - - - - - -

fn main() = {
    
    # Number of fibonacci numbers to be computed
    let x = 12;

    let a = 0;
    let b = 1;

    while x > 0 {
        
        let c = a + b;
        b = a;
        a = c;
        x -= 1;
        print c;
    }
}
