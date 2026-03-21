#include <omp.h>
#include <Eigen/Core>
#include <Eigen/Sparse>
#include <iostream>
#include <vector>
#include <chrono>
#include "util.hpp"

int main(int argc, char **argv)
{
	if (argc < 4)
	{
		// NUMA_optimize=true only works as intended if the process calling this function has a NUMA policy that allocates memory locally (e.g., not interleaved,etc.)
		std::cerr << "Usage: " << argv[0] << " <matrix.bin> <iterations> <NUMA_optimize 0/1>\n";
		return 1;
	}

	srand(42);

	int max_iterations = std::stoi(argv[2]);
	bool NUMA_optimize = (std::stoi(argv[3]) != 0);
	CustomSparseMatrix A = load_binary_matrix(argv[1], NUMA_optimize);

	CustomVector x(A.cols());
	CustomVector y(A.rows());

	if (NUMA_optimize)
	{
#pragma omp parallel for schedule(static)
		for (int i = 0; i < A.rows(); i++)
			y[i] = 0.0;

#pragma omp parallel for schedule(static)
		for (int i = 0; i < A.cols(); i++)
			x[i] = static_cast<Scalar>(rand()) / RAND_MAX;
	}
	else
	{
		y.setZero();
		x.setRandom();
	}

	auto start = std::chrono::high_resolution_clock::now();

	auto *row_ptr = A.outerIndexPtr();
	auto *col_idx = A.innerIndexPtr();
	auto *values = A.valuePtr();

	for (int iter = 0; iter < max_iterations; ++iter)
	{
#pragma omp parallel for schedule(static)
		for (int i = 0; i < A.rows(); i++)
		{
			Scalar sum = 0;
			for (int j = row_ptr[i]; j < row_ptr[i + 1]; j++)
			{
				sum += values[j] * x[col_idx[j]];
			}
			y[i] = sum;
		}
	}

	auto end = std::chrono::high_resolution_clock::now();
	std::chrono::duration<double> elapsed = end - start;

	double gflops = (2.0 * A.nonZeros() * max_iterations) / (elapsed.count() * 1e9);

	std::cout << "EXTRA_DATA,"
			  << elapsed.count() << ","
			  << gflops << std::endl;

	return 0;
}