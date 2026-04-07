#include "util.hpp"
#include <chrono>
#include <iostream>
#include <string>

template <typename T>
double timer(T func) {
    auto start = std::chrono::high_resolution_clock::now();
    func();
    auto end = std::chrono::high_resolution_clock::now();
    return std::chrono::duration<double>(end - start).count();
}

int main(int argc, char* argv[]) {
    if (argc < 3) {
        std::cout << "Usage: " << argv[0] << " <input.mtx> <iterations>" << std::endl;
        return 1;
    }

    const std::string mtx_path = argv[1];
    const std::string bin_path = mtx_path + ".bin";
    const int iterations = std::stoi(argv[2]);

    std::cout << "Benchmarking Matrix: " << mtx_path << std::endl;
    
    // 1. Convert MTX to BIN once before timing
    std::cout << "Step 1: Converting to binary format..." << std::endl;
    CustomSparseMatrix conversion_mat;
    if (write_binary_matrix(mtx_path, bin_path, conversion_mat) != 0) {
        return 1;
    }

    // 2. Measure MTX loading
    std::cout << "Step 2: Loading MTX " << iterations << " times..." << std::endl;
    double mtx_total = 0;
    for (int i = 0; i < iterations; ++i) {
        mtx_total += timer([&]() {
            std::ifstream f(mtx_path);
            CustomSparseMatrix mat;
            fast_matrix_market::read_matrix_market_eigen(f, mat);
            mat.makeCompressed();
        });
    }

    // 3. Measure BIN loading
    std::cout << "Step 3: Loading BIN " << iterations << " times..." << std::endl;
    double bin_total = 0;
    for (int i = 0; i < iterations; ++i) {
        bin_total += timer([&]() {
            CustomSparseMatrix mat = load_binary_matrix(bin_path);
        });
    }

    // --- Output Statistics ---
    double avg_mtx = mtx_total / iterations;
    double avg_bin = bin_total / iterations;

    std::cout << "\n================ RESULTS ================" << std::endl;
    std::cout << "Average MTX Load: " << avg_mtx << " seconds" << std::endl;
    std::cout << "Average BIN Load: " << avg_bin << " seconds" << std::endl;
    std::cout << "Speedup Factor:   " << (avg_mtx / avg_bin) << "x" << std::endl;
    std::cout << "=========================================" << std::endl;

    return 0;
}