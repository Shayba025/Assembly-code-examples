#include <stdio.h>

long sum_digits (long n);

int main (void) {
  long n = 472;
  long result = sum_digits (n);
  printf ("sum digits(%ld) = %ld\n",n, result);
  return 0;
}
