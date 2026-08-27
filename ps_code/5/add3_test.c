/* add3_test.c -- a C driver for add3.asm.
 *
 * add3.asm defines a function but no main(), so it cannot be linked on its own.
 * The ./asm and ./debug scripts automatically compile and link this file
 * whenever a <name>_test.c sits next to <name>.asm.
 *
 *     ./asm "ps_code/5/add3.asm"            (from the "code examples" folder)
 *     ./asm "ps_code/5/add3.asm" 7 8 9
 */
#include <stdio.h>
#include <stdlib.h>

/* Declared here, defined in assembly. The C compiler emits an ordinary call
 * that passes a in rdi, b in rsi and c in rdx, and expects the result in rax --
 * which is exactly what add3.asm implements. */
long add3(long a, long b, long c);

int main(int argc, char *argv[])
{
    long a = 10, b = 20, c = 30;

    if (argc == 4) {
        a = atol(argv[1]);
        b = atol(argv[2]);
        c = atol(argv[3]);
    }

    printf("add3(%ld, %ld, %ld) = %ld\n", a, b, c, add3(a, b, c));
    printf("C says              = %ld\n", a + b + c);
    return 0;
}
