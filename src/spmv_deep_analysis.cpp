#define EIGEN_USE_THREADS
#include <omp.h>
#include <Eigen/Core>
#include <Eigen/Sparse>
#include <iostream>
#include <vector>
#include <chrono>
#include "util.hpp"

int main(int argc, char **argv)
{
	if (argc < 3)
	{
		std::cerr << "Usage: " << argv[0] << " <matrix.bin> <iterations>\n";
		return 1;
	}

	srand(42);

	auto io_start = std::chrono::high_resolution_clock::now();
	CustomSparseMatrix A = load_binary_matrix(argv[1]);
	auto io_end = std::chrono::high_resolution_clock::now();

	std::chrono::duration<double> io_elapsed = io_end - io_start;

	std::cout << "IO_LOAD,"
			  << io_elapsed.count()
			  << std::endl;

	int max_iterations = std::stoi(argv[2]);

	CustomVector x = CustomVector::Random(A.cols());
	CustomVector y = CustomVector::Zero(A.rows());

	auto *row_ptr = A.outerIndexPtr();
	auto *col_idx = A.innerIndexPtr();
	auto *values = A.valuePtr();

	for (int iter = 0; iter < max_iterations; ++iter)
	{
		auto start = std::chrono::high_resolution_clock::now();

#pragma omp parallel for
		for (int i = 0; i < A.rows(); i++)
		{
			Scalar sum = 0;
			for (int j = row_ptr[i]; j < row_ptr[i + 1]; j++)
			{
				sum += values[j] * x[col_idx[j]];
			}
			y[i] = sum;
		}

		auto end = std::chrono::high_resolution_clock::now();
		std::chrono::duration<double> elapsed = end - start;

		double gflops = (2.0 * A.nonZeros()) / (elapsed.count() * 1e9);

		std::cout << "ITER,"
				  << iter << ","
				  << elapsed.count() << ","
				  << gflops
				  << std::endl;
	}

	return 0;
}