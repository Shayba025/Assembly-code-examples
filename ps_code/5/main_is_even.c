#include <stdio.h>

long is_even (long n);
long is_odd (long n);

int main (void)
{
   long n=7;
   printf ("%ld is even %ld\n",n,  is_even(n) );
   printf ("%ld is odd %ld\n", n, is_odd(n) );
  return (0);
}
