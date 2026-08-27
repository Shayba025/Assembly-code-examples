/* sum_digits_test.c -- a C driver for sum_digits.asm.
 *
 * sum_digits.asm defines a function but no main(). The ./asm and ./debug
 * scripts link this file automatically because it is named <name>_test.c.
 *
 *     ./asm "ps_code/5/sum_digits.asm"           (from "code examples")
 *     ./asm "ps_code/5/sum_digits.asm" 98765
 */
#include <stdio.h>
#include <stdlib.h>

long sum_digits(long n);        /* defined in sum_digits.asm */

/* the same thing in C, so you can compare */
static long reference(long n)
{
    long s = 0;
    while (n > 0) { s += n % 10; n /= 10; }
    return s;
}

int main(int argc, char *argv[])
{
    if (argc > 1) {
        long n = atol(argv[1]);
        printf("sum_digits(%ld) = %ld   (C says %ld)\n",
               n, sum_digits(n), reference(n));
        return 0;
    }

    for (long n = 0; n <= 9999; n++) {
        long got = sum_digits(n), want = reference(n);
        if (got != want) {
            printf("MISMATCH at %ld: assembly says %ld, C says %ld\n",
                   n, got, want);
            return 1;
        }
    }
    printf("sum_digits agrees with C for every n in 0..9999\n");
    printf("sum_digits(12345) = %ld\n", sum_digits(12345));
    return 0;
}
