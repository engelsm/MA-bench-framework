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

// Apply patch for this file to work:
// git -C external/eigen apply ../../eigen_bench_instrumentation.patch

struct ManualOp
{
	// Spectra expects the following structure for the operator struct. See https://spectralib.org/doc/sparsesymmatprod_8h_source as an example.
	using Scalar = ::Scalar;

	const CustomSparseMatrix &m_mat;

	ManualOp(const CustomSparseMatrix &mat) : m_mat(mat) {}

	Eigen::Index rows() const { return m_mat.rows(); }
	Eigen::Index cols() const { return m_mat.cols(); }

	mutable double eigensolver_spmv_time = 0;

	void perform_op(const Scalar *x_in, Scalar *y_out) const
	{

		// Spectra passes raw memory pointers to perform_op, thus we need to map them to Eigen types.
		// x length is equal to given matrix cols (needed for element wise multiplication).
		Eigen::Map<const CustomVector> x{x_in, m_mat.cols()};
		// y length is equal to given matrix rows (result of multiplication).
		Eigen::Map<CustomVector> y{y_out, m_mat.rows()};

		double start_time = omp_get_wtime();
		// Calling .noalias() will directly invoke the specialized Eigen kernel based on the types of factors.
		// In this case this leads to the use of sparse_time_dense_product_impl (defined in MA-Bench-Framework/external/eigen/Eigen/src/SparseCore/SparseDenseProduct.h).
		// This function is parallelized internally by Eigen when EIGEN_USE_THREADS is defined.
		// See https://libeigen.gitlab.io/eigen/docs-nightly/TopicMultiThreading.html
		y.noalias() = m_mat * x;
		double end_time = omp_get_wtime();
		double duration = end_time - start_time;
		eigensolver_spmv_time += (duration);
	}
};

// We shall split t_mgmt into t_mgmt and t_omp_overhead in the evaluation scripts.
void print_output(double t_spmv, double t_mgmt, int n_ops)
{
	std::cout << "EXTRA_DATA," << t_spmv << "," << t_mgmt << "," << n_ops << std::endl;
}

/* Every SpMV operation in a single solve process operates on the same matrix A, but a changing vector.
 * Thus, the sole time per SpMV operation might change over the course of the solving process for both
 * linear system solvers and eigenvalue solvers. (Testing showed increased times for the first few SpMVs,
 * but after some iterations the time stabilizes.)
 *
 * We fix iterations for all solvers and make convergence impossible.
 * Linear solver params:
 * -Max iterations
 * -Preconditioner
 *
 * Eigenvalue solver params:
 * -Number of restarts
 * -Number of requested eigenvalues
 * -Krylov subspace size
 */

template <typename SolverType>
void run_linear_solver(const CustomSparseMatrix &A, int max_iter)
{
	CustomVector b = CustomVector::Ones(A.rows());
	CustomVector x;

	SolverType solver;
	// We set the tolerance to 0.0 and limit the max iterations to ensure the solver does not exit early due to convergence. For benchmarking
	// purposes, we want to measure a predictable number of iterations without the solver stopping when it finds a "good enough" solution.
	solver.setMaxIterations(max_iter);
	solver.setTolerance(0);

	// Reset SpMV counter
	Eigen::internal::linsolver_spmv_time = 0.0;

	double start_time = omp_get_wtime();
	solver.compute(A);
	// The result needs to be assigned to a variable, otherwise the compiler optimizes away the computation.
	x = solver.solve(b);
	double end_time = omp_get_wtime();

	double t_total = end_time - start_time;
	// I added this variable to Eigen's internal namespace to track SpMV time in ConjugateGradient and BiCGSTAB. The value is updated in their respective source files.
	// See MA-bench-framework/external/eigen/Eigen/src/IterativeLinearSolvers/ConjugateGradient.h & MA-bench-framework/external/eigen/Eigen/src/IterativeLinearSolvers/BiCGSTAB.h
	double t_spmv = Eigen::internal::linsolver_spmv_time;
	double t_mgmt = t_total - t_spmv;
	print_output(t_spmv, t_mgmt, solver.iterations());
}

// See Chapter 4 & 5 of http://li.mit.edu/Archive/Activities/Archive/CourseWork/Ju_Li/MITCourses/18.335/Doc/ARPACK/Lehoucq97.pdf for the theory behind IRAM/IRLM
template <typename SolverType, typename OpType>
void run_eigen_solver(const CustomSparseMatrix &A, int max_restarts, int n_eigvals, int n_bvecs)
{
	OpType op(A);
	SolverType solver(op, n_eigvals, n_bvecs);

	double start_time = omp_get_wtime();
	solver.init();
	// We set the tolerance to 0.0 and limit the max iterations to ensure the solver does not exit early due to convergence. For benchmarking
	// purposes, we want to measure a predictable number of iterations without the solver stopping when it finds a "good enough" solution.
	solver.compute(Spectra::SortRule::LargestMagn, max_restarts, 0.0);
	double end_time = omp_get_wtime();

	double t_total = end_time - start_time;
	double t_spmv = op.eigensolver_spmv_time;
	double t_mgmt = t_total - t_spmv;

	//.num_iterations() would be the number of restarts.
	//.num_operations() gives the total number of SpMV operations performed.
	print_output(t_spmv, t_mgmt, solver.num_operations());

	/* The number of SpMV operations is a variable in Spectra called m_nmatop and counted with the op_counter variable.
	 * * Definition of Variables:
	 * - n: Dimension of the matrix (rows/cols).
	 * - k: Number of eigenvalues requested (Spectra: n_eigvals / nev).
	 * - m: Dimension of the Krylov subspace / basis size (Spectra: n_bvecs / ncv).
	 * - max_restarts: Maximum number of Arnoldi/Lanczos update cycles.
	 *
	 * We track down the formula for the number of SpMV operations in the following way:
	 * * 1. init():
	 * Calls 2 SpMV operations.
	 * - The first (Arnoldi.h:154) ensures the starting vector is in the range of A.
	 * - The second (Arnoldi.h:174) computes the first Ritz value and the initial residual f.
	 *
	 * 2. First call to compute() -> factorize_from(1, m, op_counter):
	 * Builds the initial Krylov subspace from the 2nd to the m-th vector.
	 * - Generates exactly (m - 1) SpMV operations.
	 *
	 * 3. Implicit Restarts (for i = 0 to max_restarts - 1):
	 * Each restart reduces the basis from m down to k and then calls factorize_from(k, m, op_counter).
	 * - Each call generates exactly (m - k) SpMV operations to refill the basis.
	 *
	 * Total SpMV Formula:
	 * Total = 2 + (m - 1) + [max_restarts * (m - k)] + X
	 * (where X represents rare extra SpMVs from numerical breakdowns in expand_basis)
	 *
	 * Example for (max_restarts=50, k=10, m=30):
	 * Total = 2 + 29 + [50 * 20] = 1031 SpMVs.
	 */
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
	// Linear solvers: Number of iterations ; Eigen solvers: Max number of restarts
	int arg1 = (argc >= 4) ? std::stoi(argv[3]) : 100;
	// Linear solvers: unused ; Eigen solvers: Number of eigenvalues to compute
	int arg2 = (argc >= 5) ? std::stoi(argv[4]) : 20;
	// Linear solvers: unused ; Eigen solvers: Number of basis vectors
	int arg3 = (argc >= 6) ? std::stoi(argv[5]) : 20;

	// Set fixed seed for reproducibility
	std::srand(42);

	CustomSparseMatrix A = load_binary_matrix(filename, false);

	if (mode == "cg")
	{
		using Solver = Eigen::ConjugateGradient<CustomSparseMatrix, Eigen::Lower | Eigen::Upper, Eigen::IdentityPreconditioner>;
		run_linear_solver<Solver>(A, arg1);
	}
	else if (mode == "bicgstab")
	{
		using Solver = Eigen::BiCGSTAB<CustomSparseMatrix, Eigen::IdentityPreconditioner>;
		// does 2 spmv per iteration
		run_linear_solver<Solver>(A, arg1);
	}
	else if (mode == "lanczos") // IRLM
	{
		using Solver = Spectra::SymEigsSolver<ManualOp>;
		run_eigen_solver<Solver, ManualOp>(A, arg1, arg2, arg3);
	}
	else if (mode == "arnoldi") // IRAM
	{
		using Solver = Spectra::GenEigsSolver<ManualOp>;
		run_eigen_solver<Solver, ManualOp>(A, arg1, arg2, arg3);
	}
	else
	{
		std::cerr << "Unknown mode: " << mode << std::endl;
		return 1;
	}

	return 0;
}