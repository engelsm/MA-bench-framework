#define EIGEN_USE_THREADS
#include <omp.h>
#include <Eigen/Core>
#include <Eigen/Sparse>
#include <iostream>
#include <vector>
#include <chrono>
#include "util.hpp"

// CONJUGATE GRADIENT METHOD FOR SPARSE MATRICES
int main(int argc, char **argv)
{
	if (argc < 3)
	{
		std::cerr << "Usage: " << argv[0] << " <matrix.bin> <iterations>\n";
		return 1;
	}

	// Load matrix and setup vectors
	CustomSparseMatrix m_mat = load_binary_matrix(argv[1]);
	int iterations = std::stoi(argv[2]);
	CustomVector x = CustomVector::Random(m_mat.cols());
	CustomVector y = CustomVector::Zero(m_mat.rows());

	// Measurement Phase
	auto start = std::chrono::high_resolution_clock::now();

	for (int iter = 0; iter < iterations; ++iter)
	{
#pragma omp parallel for
		for (Eigen::Index i = 0; i < m_mat.outerSize(); ++i)
		{
			Scalar sum = 0;
			for (CustomSparseMatrix::InnerIterator it(m_mat, i); it; ++it)
			{
				sum += it.value() * x(it.col());
			}
			y(i) = sum;
		}
	}

	auto end = std::chrono::high_resolution_clock::now();
	std::chrono::duration<double> elapsed = end - start;

	// Output only the essentials for easy parsing
	// Format: matrix, total_time, time_per_spmv, gflops
	double gflops = (2.0 * m_mat.nonZeros() * iterations) / (elapsed.count() * 1e9);

	std::cout << "EXTRA_DATA,"
			  << elapsed.count() << ","
			  << (elapsed.count() / iterations) << ","
			  << gflops << std::endl;

	return 0;
}