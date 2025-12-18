#define EIGEN_USE_THREADS
#include <omp.h>
#include <Eigen/Core>
#include <Eigen/Sparse>
#include <Spectra/SymEigsSolver.h>
#include <Spectra/MatOp/SparseSymMatProd.h>
#include <iostream>
#include <string>
#include "util.h"

// We use rowMajor for parallelization as colMajor causes write conflicts with multiple threads slowing down the computation
// Look at https://spectralib.org/doc/sparsesymmatprod_8h_source
struct ManualParallelOp
{
	// Spectra expects a type named Scalar so we redefine it
	using Scalar = ::Scalar;

	const CustomSparseMatrix &m_mat;

	ManualParallelOp(const CustomSparseMatrix &mat) : m_mat(mat) {}

	// Spectra expects these two member functions for the operator
	Eigen::Index rows() const { return m_mat.rows(); }
	Eigen::Index cols() const { return m_mat.cols(); }

	// y_out = A * x_in
	void perform_op(const Scalar *x_in, Scalar *y_out) const
	{
		// Spectra expects raw pointers for perform_op, thus we need to map them to Eigen types

		// x length is equal to given matrix cols (needed for element wise multiplication)
		Eigen::Map<const CustomVector> x{x_in, m_mat.cols()};
		// y length is equal to given matrix rows (result of multiplication)
		Eigen::Map<CustomVector> y{y_out, m_mat.rows()};

		// TODO: OpenMP optimieren
#pragma omp parallel for
		// Look at https://libeigen.gitlab.io/eigen/docs-nightly/group__TutorialSparse.html
		// Iterate over rows of the matrix
		for (Eigen::Index i = 0; i < m_mat.outerSize(); ++i)
		{
			Scalar sum = 0;
			// Iterate over non-zero elements in the current row using InnerIterator (locates non-zeros efficiently)
			for (typename CustomSparseMatrix::InnerIterator it(m_mat, i); it; ++it)
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
		std::clog << "Usage: " << argv[0] << " <matrix.dat>\n";
		return 1;
	}

	CustomSparseMatrix A = load_binary_matrix<Scalar>(argv[1]);
	ManualParallelOp op(A);

	int eigen_vecs = 2;
	int lanczos_vecs = 20;

	Spectra::SymEigsSolver<ManualParallelOp> solver(op, eigen_vecs, lanczos_vecs);
	solver.init();
	solver.compute();

	if (solver.info() == Spectra::CompInfo::Successful)
	{
		Eigen::VectorXd evals = solver.eigenvalues();
		std::cout << "Eigenvalues: " << evals.transpose() << std::endl;
	}
	else
	{
		std::cerr << "Solver did not converge." << std::endl;
	}

	return 0;
}