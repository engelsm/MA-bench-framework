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

	CustomSparseMatrix A = load_binary_matrix(argv[1]);
	int max_iterations = std::stoi(argv[2]);
	CustomVector x = CustomVector::Random(A.cols());
	CustomVector y = CustomVector::Zero(A.rows());

	auto start = std::chrono::high_resolution_clock::now();

	for (int iter = 0; iter < max_iterations; ++iter)
	{
#pragma omp parallel for
		for (Eigen::Index i = 0; i < A.outerSize(); ++i)
		{
			Scalar sum = 0;
			for (CustomSparseMatrix::InnerIterator it(A, i); it; ++it)
			{
				sum += it.value() * x(it.col());
			}
			y(i) = sum;
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