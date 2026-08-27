/* is_even_test.c -- a C driver for is_even.asm.
 *
 * is_even.asm defines two mutually recursive functions but no main(). The ./asm
 * and ./debug scripts link this file automatically because it is named
 * <name>_test.c.
 *
 *     ./asm "ps_code/5/is_even.asm"          (from "code examples")
 *     ./asm "ps_code/5/is_even.asm" 7
 *
 * Careful: these functions recurse ONCE PER UNIT, so is_even(1000000) is a
 * million stack frames deep and will overflow the stack. Keep n small.
 */
#include <stdio.h>
#include <stdlib.h>

long is_even(long n);           /* defined in is_even.asm */
long is_odd(long n);            /* ...and so is this one */

int main(int argc, char *argv[])
{
    if (argc > 1) {
        long n = atol(argv[1]);
        printf("n = %ld: is_even = %ld, is_odd = %ld   (C says even = %d)\n",
               n, is_even(n), is_odd(n), (n % 2) == 0);
        return 0;
    }

    for (long n = 0; n <= 10; n++)
        printf("n = %2ld   is_even = %ld   is_odd = %ld   (C: even = %d)\n",
               n, is_even(n), is_odd(n), (n % 2) == 0);
    return 0;
}
