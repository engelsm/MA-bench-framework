#define EIGEN_USE_THREADS
#include <omp.h>
#include <Eigen/Core>
#include <Eigen/Sparse>
#include <Spectra/SymEigsSolver.h>
#include <Spectra/GenEigsSolver.h>
#include <Spectra/MatOp/SparseSymMatProd.h>
#include <iostream>
#include <string>
#include <chrono>
#include "util.h"

// Look at https://spectralib.org/doc/sparsesymmatprod_8h_source
struct ManualParallelOp
{
	// Spectra expects a type named Scalar so we redefine it.
	using Scalar = ::Scalar;

	const CustomSparseMatrix &m_mat;

	mutable double total_spmv_time = 0;

	ManualParallelOp(const CustomSparseMatrix &mat) : m_mat(mat) {}

	// Spectra expects these two member functions for the operator.
	Eigen::Index rows() const { return m_mat.rows(); }
	Eigen::Index cols() const { return m_mat.cols(); }

	// y_out = A * x_in
	void perform_op(const Scalar *x_in, Scalar *y_out) const
	{
		double start = omp_get_wtime();

		// Spectra passes raw memory pointers to perform_op, thus we need to map them to Eigen types.
		// x length is equal to given matrix cols (needed for element wise multiplication).
		Eigen::Map<const CustomVector> x{x_in, m_mat.cols()};
		// y length is equal to given matrix rows (result of multiplication).
		Eigen::Map<CustomVector> y{y_out, m_mat.rows()};

		/**
		 * For large matrices this might be more efficient:
		 * #pragma omp parallel for default(none) shared(x, y, m_mat) schedule(guided)
		 * - default(none) & shared: Explicitly specify variable sharing to avoid accidental data races.
		 * - schedule(guided): The rows of our sparse matrices will often times have
		 *   varying amounts of non-zero elements. This directive helps to balance the workload
		 *   among threads by dynamically assigning chunks of iterations depending on their size.
		 *   (Threads that finish early can take on more work.)
		 */
#pragma omp parallel for
		// Look at https://libeigen.gitlab.io/eigen/docs-nightly/group__TutorialSparse.html
		// Iterate over rows of the matrix as we use RowMajor storage (defined in util.h).
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
		total_spmv_time += (omp_get_wtime() - start);
	}
};

template <typename SolverType, typename OpType>
void run_solver(const CustomSparseMatrix &A, int n_eigvals, int n_bvecs, const std::string &filename, const std::string &mode)
{
	OpType op(A);
	SolverType solver(op, n_eigvals, n_bvecs);
	solver.init();

	auto start_time = std::chrono::high_resolution_clock::now();

	solver.compute();

	auto end_time = std::chrono::high_resolution_clock::now();
	std::chrono::duration<double> elapsed = end_time - start_time;

	double t_total = elapsed.count();
	double t_spmv = op.total_spmv_time;
	double t_mgmt = t_total - t_spmv;
	int actual_ops = solver.num_operations();
	double t_per_op = (actual_ops > 0) ? (t_spmv / actual_ops) : 0;

	std::cout << "RESULT,"
			  << filename << ","
			  << mode << ","
			  << omp_get_max_threads() << ","
			  << t_total << ","
			  << t_spmv << ","
			  << t_mgmt << ","
			  << solver.num_iterations() << ","
			  << t_per_op << std::endl;

	if (solver.info() != Spectra::CompInfo::Successful)
	{
		std::clog << "Info: Solver stopped (Code: " << int(solver.info()) << ")" << std::endl;
	}
	else
	{
		std::cout << "EVs: " << solver.eigenvalues().transpose() << std::endl;
	}
}

int main(int argc, char **argv)
{
	if (argc != 5)
	{
		std::clog << "Usage: " << argv[0] << " <matrix.dat> <mode: lanczos|arnoldi> <n_eigvals> <n_bvecs>\n";
		return 1;
	}

	std::string filename = argv[1];
	std::string mode = argv[2];
	int n_eigvals = std::stoi(argv[3]);
	int n_bvecs = std::stoi(argv[4]);

	CustomSparseMatrix A = load_binary_matrix(filename);

	if (mode == "lanczos")
	{
		using Solver = Spectra::SymEigsSolver<ManualParallelOp>;
		run_solver<Solver, ManualParallelOp>(A, n_eigvals, n_bvecs, filename, mode);
	}
	else if (mode == "arnoldi")
	{
		using Solver = Spectra::GenEigsSolver<ManualParallelOp>;
		run_solver<Solver, ManualParallelOp>(A, n_eigvals, n_bvecs, filename, mode);
	}
	else
	{
		std::cerr << "Unknown mode: " << mode << std::endl;
		return 1;
	}

	return 0;
}