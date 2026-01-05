#include <iostream>
#include <omp.h>

int main() {

    #pragma omp parallel
    {
        int tid = omp_get_thread_num();
        int nthreads = omp_get_num_threads();

        #pragma omp critical
        std::cout << "Hello from thread " << tid << " / " << nthreads << std::endl;
    }

    // Großer Workload
    #pragma omp parallel
    {
        double sum = 0;
        #pragma omp for
        for(long long i = 0; i < 100000000LL; i++) {  // <--- 1e8 zu 100000000LL ändern
            sum += i*0.0000001;
        }
        #pragma omp critical
        std::cout << "Thread finished work, partial sum = " << sum << std::endl;
    }

    return 0;
}