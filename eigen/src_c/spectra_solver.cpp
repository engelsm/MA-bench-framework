#include <Eigen/Sparse>
#include <Eigen/Dense>
#include <Spectra/SymEigsSolver.h>
#include <Spectra/MatOp/SparseSymMatProd.h>
#include <iostream>
#include "load_binary_matrix.h"
#include <omp.h>

using namespace Eigen;
using namespace Spectra;

// COMPILE WITH:
//  g++ -O3 -march=znver4 -fopenmp -I$EBROOTEIGEN -I$HOME/libs/spectra/include spectra_solver.cpp -o spectra_solver

void run_spectra_solver(const SparseMatrix<double> &A)
{

    int k = 2;
    int ncv = 20;

    SparseSymMatProd<double> op(A);
    // Implicitly restarted Lanczos solver for symmetric eigenvalue problems
    SymEigsSolver<SparseSymMatProd<double>> solver(op, k, ncv);

    solver.init();
    solver.compute();

    if (solver.info() != CompInfo::Successful)
    {
        std::cerr << "Eigenvalue computation failed!\n";
        std::exit(1);
    }

    MatrixXd V = solver.eigenvectors();
    VectorXd vals = solver.eigenvalues();
}

int main(int argc, char **argv)
{
    if (argc != 2)
    {
        std::cerr << "Usage: spectra_solver <binary_matrix.dat>\n";
        return 1;
    }
    Eigen::initParallel();

    auto n = Eigen::nbThreads();
    std::cout << "Eigen " << n << " threads.\n";
    std::cout << "OMP  " << omp_get_max_threads() << " threads" << std::endl;
    auto A = load_binary_matrix(argv[1]);

    run_spectra_solver(A);

    return 0;
}