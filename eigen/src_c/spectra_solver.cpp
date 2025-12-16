#include <Eigen/Sparse>
#include <Eigen/Dense>
#include <Spectra/SymEigsSolver.h>
#include <Spectra/MatOp/SparseSymMatProd.h>

#include <iostream>
#include "load_binary_matrix.h" 

using namespace Eigen;
using namespace Spectra;

int main(int argc, char** argv)
{
    if(argc != 2)
    {
        std::cerr << "Usage: spectra_solver <binary_matrix.dat>\n";
        return 1;
    }

    // Lade die komprimierte Binary-Matrix
    auto A = load_binary_matrix(argv[1]);

    int k = 2;       // Anzahl der Eigenwerte
    int ncv = 20;    // Lanczos-Unterraum

    SparseSymMatProd<double> op(A);
    SymEigsSolver<SparseSymMatProd<double>> solver(op, k, ncv);

    solver.init();
    solver.compute();

    if(solver.info() != CompInfo::Successful)
    {
        std::cerr << "Eigenvalue computation failed!\n";
        return 1;
    }

    MatrixXd V = solver.eigenvectors();
    VectorXd vals = solver.eigenvalues();

    std::cout << "Top " << k << " Eigenvalues:\n";
    for(int i = 0; i < vals.size(); i++)
        std::cout << vals[i] << "\n";

    return 0;
}
