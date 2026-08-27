/* asm_demo_test.c -- a C driver for asm_demo.asm.
 *
 * asm_demo.asm defines a function but no main(). The ./asm and ./debug scripts
 * link this file automatically because it is named <name>_test.c.
 *
 *     echo hello | ./asm "ps_code/5/asm_demo.asm"      (from "code examples")
 *
 * asm_demo() writes one line to stdout, one to stderr, then reads up to 50
 * bytes from stdin and echoes them back -- all through raw system calls, with
 * no C library involved. To see stdout and stderr really are separate streams:
 *
 *     echo hi | ./asm "ps_code/5/asm_demo.asm" 2>/dev/null   # stderr hidden
 *     echo hi | ./asm "ps_code/5/asm_demo.asm" 1>/dev/null   # stdout hidden
 */
#include <stdio.h>

void asm_demo(void);            /* defined in asm_demo.asm */

int main(void)
{
    asm_demo();
    return 0;
}
