#include <Eigen/Sparse>
#include <Eigen/Dense>
#include <Spectra/SymEigsSolver.h>
#include <Spectra/DavidsonSymEigsSolver.h>
#include <Spectra/MatOp/SparseSymMatProd.h>
#include <iostream>
#include <string>
#include "load_binary_matrix.h"
#include <omp.h>

using namespace Eigen;
using namespace Spectra;

int main(int argc, char **argv)
{
	if (argc < 3)
	{
		std::cerr << "Usage: " << argv[0] << " <lanczos|davidson> <matrix.dat>\n";
		return 1;
	}

	std::string algo = argv[1];
	auto A = load_binary_matrix(argv[2]);
	SparseSymMatProd<double> op(A);

	int k = 2;
	int ncv = 20;

	if (algo == "lanczos")
	{
		SymEigsSolver<SparseSymMatProd<double>> solver(op, k, ncv);
		solver.init();
		solver.compute();

		if (solver.info() == CompInfo::Successful)
		{
			VectorXd evals = solver.eigenvalues();
			std::cout << "Lanczos_Eigenvalues: " << evals.transpose() << std::endl;
		}
		else
		{
			std::cerr << "Lanczos failed to converge." << std::endl;
		}
	}
	else if (algo == "davidson")
	{
		DavidsonSymEigsSolver<SparseSymMatProd<double>> solver(op, k);
		solver.compute();

		if (solver.info() == CompInfo::Successful)
		{
			VectorXd evals = solver.eigenvalues();
			std::cout << "Davidson_Eigenvalues: " << evals.transpose() << std::endl;
		}
		else
		{
			std::cerr << "Davidson failed to converge." << std::endl;
		}
	}
	else
	{
		std::cerr << "Error: Use 'lanczos' or 'davidson'\n";
		return 1;
	}

	return 0;
}