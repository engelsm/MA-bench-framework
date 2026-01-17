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
		eigensolver_spmv_time += 1;
	}
};

void print_output(double t_spmv, double t_mgmt, int n_ops)
{
	std::cout << "EXTRA_DATA," << t_spmv << "," << t_mgmt << "," << n_ops << std::endl;
}

template <typename SolverType>
void run_linear_solver(const CustomSparseMatrix &A, int max_iter)
{
	CustomVector b = CustomVector::Ones(A.rows());
	CustomVector x;

	SolverType solver;
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

template <typename SolverType, typename OpType>
void run_eigen_solver(const CustomSparseMatrix &A, int max_restarts, int n_eigvals, int n_bvecs)
{
	OpType op(A);
	SolverType solver(op, n_eigvals, n_bvecs);

	double start_time = omp_get_wtime();
	solver.init();
	// We set the tolerance to 0.0 and limit the max iterations (here 1) to ensure the solver does not exit early due to convergence. For benchmarking
	// purposes, we want to measure a predictable number of iterations without the solver stopping when it finds a "good enough" solution.
	solver.compute(Spectra::SortRule::LargestMagn, max_restarts, 0.0);
	double end_time = omp_get_wtime();

	double t_total = end_time - start_time;
	double t_spmv = op.eigensolver_spmv_time;
	double t_mgmt = t_total - t_spmv;

	print_output(t_spmv, t_mgmt, solver.num_iterations());
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

	CustomSparseMatrix A = load_binary_matrix(filename);

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