#include <stdio.h>

extern void asm_demo(void);

int main (void)
{
   char name [100];
   
   printf ("Enter your name: ");
   fflush (stdout);   // stdout is buffered 
   
  if (fgets (name, sizeof (name), stdin) == NULL) {
    fprintf (stderr, "Error, failed to read from stdin\n");
    return 1;
    }

   printf ("Hello, %s", name);
   fprintf (stderr, "This is an error message sent to stderr \n");
   
   asm_demo();   // call assembly demonstration
  
   return 0;
}
