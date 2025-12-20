#define EIGEN_USE_THREADS
#include <omp.h>
#include <Eigen/Core>
#include <Eigen/Sparse>
#include <Spectra/SymEigsSolver.h>
#include <Spectra/GenEigsSolver.h>
#include <Spectra/MatOp/SparseSymMatProd.h>
#include <iostream>
#include <string>
#include "util.h"

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

		/**
		 * For large matrices this might be more efficient:
		 * #pragma omp parallel for default(none) shared(x, y, m_mat) schedule(guided)
		 * - default(none) & shared: Explicitly specify variable sharing to avoid accidental data races.
		 * - schedule(guided): The rows of our sparse matrices will often times have
		 *   varying amounts of non-zero elements. This directive helps to balance the workload
		 *   among threads by dynamically assigning chunks of iterations depending on their size.
		 *   (Threads that finish early can take on more work.)
		 */
#pragma omp parallel for
		// Look at https://libeigen.gitlab.io/eigen/docs-nightly/group__TutorialSparse.html
		// Iterate over rows of the matrix as we use RowMajor storage (defined in util.h)
		for (Eigen::Index i = 0; i < m_mat.outerSize(); ++i)
		{
			Scalar sum = 0;
			// While non-zero values are stored sequentially in memory for the custom CSR binary format
			// (and most other sparse matrix formats), we need the InnerIterator to retrieve the associated
			// column index (it.col()) for each value. This allows us to map the matrix element to the correct
			// entry in vector x.
			for (typename CustomSparseMatrix::InnerIterator it(m_mat, i); it; ++it)
			{
				sum += it.value() * x(it.col());
			}
			y(i) = sum;
		}
	}
};

template <typename SolverType>
void run_solver(SolverType &solver)
{
	solver.init();
	solver.compute();
	if (solver.info() == Spectra::CompInfo::Successful)
	{
		//.real() cuts off imaginary part (0 for symmetric case) but just to be aware for the general case
		std::cout << "Eigenvalues: " << solver.eigenvalues().real().transpose() << std::endl;
		std::cout << "Iterations: " << solver.num_iterations() << std::endl;
	}
	else
	{
		std::cerr << "Solver did not converge." << std::endl;
	}
}

int main(int argc, char **argv)
{
	if (argc < 3)
	{
		std::clog << "Usage: " << argv[0] << " <matrix.dat> <mode: lanczos|arnoldi>\n";
		return 1;
	}

	std::string filename = argv[1];
	std::string mode = argv[2];

	CustomSparseMatrix A = load_binary_matrix(filename);
	ManualParallelOp op(A);

	int n_eigs = 2;
	int n_cv = 20;

	if (mode == "lanczos")
	{
		std::cout << "Running Symmetric Solver (Lanczos)..." << std::endl;
		Spectra::SymEigsSolver<ManualParallelOp> solver(op, n_eigs, n_cv);
		run_solver(solver);
	}
	else if (mode == "arnoldi")
	{
		std::cout << "Running General Solver (Arnoldi)..." << std::endl;
		Spectra::GenEigsSolver<ManualParallelOp> solver(op, n_eigs, n_cv);
		run_solver(solver);
	}
	else
	{
		std::cerr << "Unknown mode: " << mode << ". Use 'lanczos' or 'arnoldi'." << std::endl;
		return 1;
	}

	return 0;
}