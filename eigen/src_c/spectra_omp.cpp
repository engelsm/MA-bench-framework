#define EIGEN_USE_THREADS
#include <omp.h>
#include <Eigen/Core>
#include <Eigen/Sparse>
#include <Spectra/SymEigsSolver.h>
#include <Spectra/MatOp/SparseSymMatProd.h>
#include <iostream>
#include <string>
#include "load_binary_matrix.h"

using namespace Eigen;
using namespace Spectra;

struct ManualParallelOp
{
	using Scalar = double;

	const SparseMatrix<double, RowMajor> &m_mat;
	ManualParallelOp(const SparseMatrix<double, RowMajor> &mat) : m_mat(mat) {}

	int rows() const { return (int)m_mat.rows(); }
	int cols() const { return (int)m_mat.cols(); }

	void perform_op(const double *x_in, double *y_out) const
	{
		Map<const VectorXd> x(x_in, m_mat.cols());
		Map<VectorXd> y(y_out, m_mat.rows());

#pragma omp parallel for
		for (int i = 0; i < (int)m_mat.outerSize(); ++i)
		{
			double sum = 0;
			for (SparseMatrix<double, RowMajor>::InnerIterator it(m_mat, i); it; ++it)
			{
				sum += it.value() * x(it.col());
			}
			y(i) = sum;
		}
	}
};

int main(int argc, char **argv)
{
	if (argc < 2)
	{
		std::cerr << "Usage: " << argv[0] << " <matrix.dat>\n";
		return 1;
	}

	int max_threads = omp_get_max_threads();
	Eigen::initParallel();
	Eigen::setNbThreads(max_threads);
	std::cout << "Erzwinge Parallelisierung auf " << max_threads << " Threads." << std::endl;

	SparseMatrix<double, RowMajor> A = load_binary_matrix(argv[1]);

	ManualParallelOp op(A);

	SymEigsSolver<ManualParallelOp> solver(op, 2, 20);
	solver.init();
	solver.compute();

	if (solver.info() == CompInfo::Successful)
	{
		std::cout << "Eigenwerte: " << solver.eigenvalues().transpose() << std::endl;
	}
	else
	{
		std::cerr << "Solver konnte nicht konvergieren." << std::endl;
	}

	return 0;
}