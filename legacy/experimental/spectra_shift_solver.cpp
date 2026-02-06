#include <Eigen/Sparse>
#include <Eigen/Dense>
#include <Eigen/SparseCholesky>
#include <Spectra/SymEigsShiftSolver.h>
#include <Spectra/MatOp/SparseSymShiftSolve.h>
#include <iostream>
#include "load_binary_matrix.h"
#include <omp.h>

using namespace Eigen;
using namespace Spectra;

// COMPILE WITH:
// g++ -O3 -march=znver4 -fopenmp -I$EBROOTEIGEN -I$HOME/libs/spectra/include spectra_shift_solver.cpp -o spectra_shift_solver

void run_spectra_shift_solver(const SparseMatrix<double> &A)
{
	int k = 2;			// Anzahl gesuchte Eigenwerte
	int ncv = 20;		// Hilfsparameter
	double sigma = 0.0; // Der Shift: Wir suchen Eigenwerte nahe 0.0

	// Shift-Invert Operation: löst (A - sigma*I)x = b
	SparseSymShiftSolve<double> op(A);
	SymEigsShiftSolver<SparseSymShiftSolve<double>> solver(op, k, ncv, sigma);

	solver.init();
	// Bei Shift-Invert suchen wir meist die Eigenwerte mit dem größten
	// Betrag der transformierten Matrix, was denen am nächsten zu sigma entspricht.
	solver.compute(SortRule::LargestMagn);

	if (solver.info() != CompInfo::Successful)
	{
		std::cerr << "Eigenvalue computation failed!\n";
		std::exit(1);
	}

	VectorXd vals = solver.eigenvalues();
	// std::cout << "Eigenvalues: " << vals.transpose() << std::endl;
}

int main(int argc, char **argv)
{
	if (argc != 2)
	{
		std::cerr << "Usage: spectra_shift_solver <binary_matrix.dat>\n";
		return 1;
	}

	Eigen::initParallel();

	std::cout << "Eigen " << Eigen::nbThreads() << " threads.\n";
	std::cout << "OMP   " << omp_get_max_threads() << " threads" << std::endl;

	auto A = load_binary_matrix(argv[1]);

	run_spectra_shift_solver(A);

	return 0;
}