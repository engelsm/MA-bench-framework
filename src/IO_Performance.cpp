#include "util.hpp"
#include <chrono>
#include <iostream>
#include <string>
#include <vector>
#include <iomanip>

template <typename T>
double timer(T func)
{
    auto start = std::chrono::high_resolution_clock::now();
    func();
    auto end = std::chrono::high_resolution_clock::now();
    return std::chrono::duration<double>(end - start).count();
}

int main(int argc, char *argv[])
{
    if (argc < 3)
    {
        std::cout << "Usage: " << argv[0] << " <input.mtx> <iterations>" << std::endl;
        return 1;
    }

    const std::string mtx_path = argv[1];
    const std::string bin_path = mtx_path + ".bin";
    const int iterations = std::stoi(argv[2]);

    std::cout << "Benchmarking Matrix: " << mtx_path << "\n"
              << std::endl;

    // 1. Preparation
    CustomSparseMatrix conversion_mat;
    write_binary_matrix(mtx_path, bin_path, conversion_mat);

    std::vector<double> mtx_times(iterations);
    std::vector<double> bin_times(iterations);

    // 2. Measure MTX
    for (int i = 0; i < iterations; ++i)
    {
        mtx_times[i] = timer([&]()
                             {
            std::ifstream f(mtx_path);
            CustomSparseMatrix mat;
            fast_matrix_market::read_matrix_market_eigen(f, mat);
            mat.makeCompressed(); });
    }

    // 3. Measure BIN
    for (int i = 0; i < iterations; ++i)
    {
        bin_times[i] = timer([&]()
                             { CustomSparseMatrix mat = load_binary_matrix(bin_path); });
    }

    std::cout << std::left << std::setw(10) << "Iter"
              << std::setw(20) << "MTX Time (s)"
              << std::setw(20) << "BIN Time (s)" << std::endl;
    std::cout << std::string(50, '-') << std::endl;

    double mtx_total = 0, bin_total = 0;
    for (int i = 0; i < iterations; ++i)
    {
        std::cout << std::left << std::setw(10) << i + 1
                  << std::setw(20) << mtx_times[i]
                  << std::setw(20) << bin_times[i];
        std::cout << std::endl;

        mtx_total += mtx_times[i];
        bin_total += bin_times[i];
    }

    // --- Statistics ---
    std::cout << "\n================ SUMMARY ================" << std::endl;
    std::cout << "Average MTX: " << (mtx_total / iterations) << " s" << std::endl;
    std::cout << "Average BIN: " << (bin_total / iterations) << " s" << std::endl;
    std::cout << "Speedup:     " << (mtx_total / bin_total) << "x" << std::endl;
    std::cout << "=========================================" << std::endl;

    return 0;
}