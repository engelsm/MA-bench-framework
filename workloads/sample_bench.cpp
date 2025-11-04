/*
 * sample_bench.cpp
 * ----------------
 * Minimal CPU-bound workload for testing.
 */

#include <iostream>

int main() {
	//volatile to prevent optimization
    volatile long sum = 0;
    for (long i = 0; i < 10000000; ++i)
	//modulo to avoid simple addition optimization
        sum += i % 10;

    std::cout << "Sum = " << sum << std::endl;
    return 0;
}
