
fn main() = {
    
    let n = 0;

    while n < 20 {
        
        let k = n;
        
        while k > 0 {
            print k;
            k -= 1;
        }

        n += 1;
    }
}

#
#    
#    let x = 10;
#    let a = 0;
#    let b = 1;
#
#    while x > 0 {
#        
#        let c = a + b;
#        b = a;
#        a = c;
#        x -= 1;
#        print c;
#    }
