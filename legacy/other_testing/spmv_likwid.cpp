#define EIGEN_USE_THREADS
#include <omp.h>
#include <Eigen/Core>
#include <Eigen/Sparse>
#include <iostream>
#include <vector>
#include <chrono>
#include "util.hpp"
// Require LIKWID, binary will fail to run if not compiled and linked with LIKWID
#include <likwid-marker.h>

int main(int argc, char **argv)
{
	if (argc < 3)
	{
		std::cerr << "Usage: " << argv[0] << " <matrix.bin> <iterations>\n";
		return 1;
	}

	LIKWID_MARKER_INIT;

	std::srand(42);

	CustomSparseMatrix m_mat = load_binary_matrix(argv[1]);
	int iterations = std::stoi(argv[2]);
	CustomVector x = CustomVector::Random(m_mat.cols());
	CustomVector y = CustomVector::Zero(m_mat.rows());

#pragma omp parallel
	{
		// Jeder Thread registriert sich einmal
		LIKWID_MARKER_THREADINIT;
		LIKWID_MARKER_REGISTER("spmv_kernel");

// Synchronisationspunkt
#pragma omp barrier

		for (int iter = 0; iter < iterations; ++iter)
		{
			// START muss innerhalb der parallelen Region stehen,
			// damit alle Threads die Hardware-Counter triggern
			LIKWID_MARKER_START("spmv_kernel");

// Das eigentliche SpMV (Worksharing)
#pragma omp for
			for (Eigen::Index i = 0; i < m_mat.outerSize(); ++i)
			{
				Scalar sum = 0;
				for (CustomSparseMatrix::InnerIterator it(m_mat, i); it; ++it)
				{
					sum += it.value() * x(it.col());
				}
				y(i) = sum;
			}

			LIKWID_MARKER_STOP("spmv_kernel");
		}
	}

	LIKWID_MARKER_CLOSE;
	return 0;
}