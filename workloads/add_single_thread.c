#include <stdio.h>
#include <math.h>

#define N 300000000

int main() {
    double x = 0;
    for (long long i = 1; i < N; i++) {
        x += sqrt(i) * sin(i);
    }
	return 0;
}