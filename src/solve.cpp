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
#include "util.hpp"
#include <iomanip>

// Scheinbar beeinflusst die Größe der Matrix das SPMV/MGMT Verhältnis.

//$Ops = n_bvecs*2 - n_eigvals + 1 ?
// const int TARGET_SPMV_OPS = 41;
// const int EIGEN_VALS_TO_COMPUTE = 20;

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
		double end = omp_get_wtime();
		double duration = end - start;
		total_spmv_time += duration;
	}
};

template <typename SolverType>
void run_linear_solver(const CustomSparseMatrix &A, int max_iter)
{
	CustomVector b = CustomVector::Ones(A.rows());
	CustomVector x;

	SolverType solver;
	solver.setMaxIterations(max_iter);
	solver.setTolerance(0);

	auto start = std::chrono::high_resolution_clock::now();
	solver.compute(A);
	x = solver.solve(b);
	auto end = std::chrono::high_resolution_clock::now();

	std::chrono::duration<double> elapsed = end - start;
	std::cout << "EXTRA_DATA,0," << elapsed.count() << "," << solver.iterations() << std::endl;
}

// Eigen runs this internally multithreaded : https://libeigen.gitlab.io/eigen/docs-nightly/TopicMultiThreading.htm
template <typename SolverType, typename OpType>
void run_eigen_solver(const CustomSparseMatrix &A, int n_eigvals, int n_bvecs)
{
	OpType op(A);
	SolverType solver(op, n_eigvals, n_bvecs);
	solver.init();

	auto start_time = std::chrono::high_resolution_clock::now();
	// Wir erzwingen 1 Restart mit n_bvecs, um exakt TARGET_SPMV_OPS zu erreichen
	solver.compute(Spectra::SortRule::LargestMagn, 1, 0.0);
	auto end_time = std::chrono::high_resolution_clock::now();

	std::chrono::duration<double> elapsed = end_time - start_time;
	double t_total = elapsed.count();
	// The spmv_time is the wall time over all threads, this means it will usually go down with more threads
	double t_spmv = op.total_spmv_time;
	double t_mgmt = t_total - t_spmv;

	std::cout << "EXTRA_DATA,"
			  << t_spmv << ","
			  << t_mgmt << ","
			  << solver.num_operations() << std::endl;

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
	if (argc < 3)
	{
		std::clog << "Usage: " << argv[0] << " <matrix.dat> <mode> <iter>\n";
		return 1;
	}

	std::string filename = argv[1];
	std::string mode = argv[2];
	int TARGET_SPMV_OPS = (argc >= 4) ? std::stoi(argv[3]) : 1000;
	// AS LONG AS THIS IS SUFFICIENTLY SMALL (~< TARGET_SPMV_OPS / 2) WE ARE GOOD
	int EIGEN_VALS_TO_COMPUTE = (argc >= 5) ? std::stoi(argv[4]) : 20;
	// Set fixed seed for reproducibility
	std::srand(42);
	CustomSparseMatrix A = load_binary_matrix(filename);

	if (mode == "cg")
	{
		using Solver = Eigen::ConjugateGradient<CustomSparseMatrix, Eigen::Lower | Eigen::Upper, Eigen::IdentityPreconditioner>;
		run_linear_solver<Solver>(A, TARGET_SPMV_OPS);
	}
	else if (mode == "bicgstab")
	{
		using Solver = Eigen::BiCGSTAB<CustomSparseMatrix, Eigen::IdentityPreconditioner>;
		// does 2 spmv per iteration
		run_linear_solver<Solver>(A, TARGET_SPMV_OPS / 2);
	}
	else if (mode == "lanczos")
	{
		using Solver = Spectra::SymEigsSolver<ManualParallelOp>;
		run_eigen_solver<Solver, ManualParallelOp>(A, EIGEN_VALS_TO_COMPUTE, TARGET_SPMV_OPS);
	}
	else if (mode == "arnoldi")
	{
		using Solver = Spectra::GenEigsSolver<ManualParallelOp>;
		run_eigen_solver<Solver, ManualParallelOp>(A, EIGEN_VALS_TO_COMPUTE, TARGET_SPMV_OPS);
	}
	else
	{
		std::cerr << "Unknown mode: " << mode << std::endl;
		return 1;
	}

	return 0;
}