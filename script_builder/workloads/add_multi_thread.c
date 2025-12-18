#include <stdio.h>
#include <math.h>
#include <omp.h>

#define N 300000000

int main() {
    double x = 0;
    #pragma omp parallel for reduction(+:x)
    for (long long i = 1; i < N; i++) {
        x += sqrt(i) * sin(i);
    }
}