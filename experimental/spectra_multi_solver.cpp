#define EIGEN_USE_THREADS
#include <omp.h>
#include <Eigen/Core>
#include <Eigen/Sparse>
#include <Spectra/SymEigsSolver.h>
#include <Spectra/DavidsonSymEigsSolver.h>
#include <Spectra/MatOp/SparseSymMatProd.h>
#include <iostream>
#include <string>
#include "load_binary_matrix.h"

using namespace Eigen;
using namespace Spectra;

int main(int argc, char **argv)
{
	if (argc < 3)
	{
		std::cerr << "Usage: " << argv[0] << " <lanczos|davidson> <matrix.dat>\n";
		return 1;
	}

	SparseMatrix<double, RowMajor> A = load_binary_matrix(argv[2]);

	using OpType = SparseSymMatProd<double, 0, RowMajor>;
	OpType op(A);

	std::string algo = argv[1];
	int k = 2;
	int ncv = 20;

	if (algo == "lanczos")
	{
		SymEigsSolver<OpType> solver(op, k, ncv);
		solver.init();
		solver.compute();

		if (solver.info() == CompInfo::Successful)
		{
			std::cout << "Lanczos_Eigenvalues: " << solver.eigenvalues().transpose() << std::endl;
		}
	}
	else if (algo == "davidson")
	{
		DavidsonSymEigsSolver<OpType> solver(op, k);
		solver.compute();

		if (solver.info() == CompInfo::Successful)
		{
			std::cout << "Davidson_Eigenvalues: " << solver.eigenvalues().transpose() << std::endl;
		}
	}
	else
	{
		std::cerr << "Error: Use 'lanczos' or 'davidson'\n";
		return 1;
	}

	return 0;
}