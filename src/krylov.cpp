#define EIGEN_USE_THREADS
#include <omp.h>
#include <sys/resource.h>
#include <Eigen/Core>
#include <Eigen/Sparse>
#include <Spectra/SymEigsSolver.h>
#include <Spectra/GenEigsSolver.h>
#include <Spectra/MatOp/SparseSymMatProd.h>
#include <iostream>
#include <string>
#include <fstream>
#include <filesystem>
#include "util.hpp"
#include "util_perf.hpp"

// Apply patch for this file to work:
// git -C external/eigen apply ../../eigen_bench_instrumentation.patch

struct Results
{
	double spmv_time;
	double mgmt_time;
	long long n_ops;
};

struct ManualOp
{
	// Spectra expects the following structure for the operator struct. See https://spectralib.org/doc/sparsesymmatprod_8h_source .
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
Results run_linear_solver(const CustomSparseMatrix &A, int max_iter, PerfGroup &pg, rusage &usage_start, rusage &usage_end)
{
	CustomVector b = CustomVector::Ones(A.rows());
	CustomVector x;

	SolverType solver;
	// We set the tolerance to 0.0 and limit the max iterations to ensure the solver does not exit early due to convergence. For benchmarking
	// purposes, we want to measure a predictable number of iterations without the solver stopping when it finds a "good enough" solution.
	solver.setMaxIterations(max_iter);
	solver.setTolerance(0);

	// I added this variable to Eigen's internal namespace to track SpMV time in ConjugateGradient and BiCGSTAB. The value is updated in their respective source files.
	// See MA-bench-framework/external/eigen/Eigen/src/IterativeLinearSolvers/ConjugateGradient.h & MA-bench-framework/external/eigen/Eigen/src/IterativeLinearSolvers/BiCGSTAB.h
	Eigen::internal::linsolver_spmv_time = 0.0;

	pg.start();
	getrusage(RUSAGE_SELF, &usage_start);

	double start_time = omp_get_wtime();
	solver.compute(A);
	// The result needs to be assigned to a variable, otherwise the compiler optimizes away the computation.
	x = solver.solve(b);
	double end_time = omp_get_wtime();

	getrusage(RUSAGE_SELF, &usage_end);
	pg.stop();

	double t_total = end_time - start_time;
	double t_spmv = Eigen::internal::linsolver_spmv_time;
	double t_mgmt = t_total - t_spmv;
	return Results{t_spmv, t_mgmt, solver.iterations()};
}

// See Chapter 4 & 5 of http://li.mit.edu/Archive/Activities/Archive/CourseWork/Ju_Li/MITCourses/18.335/Doc/ARPACK/Lehoucq97.pdf for the theory behind IRAM/IRLM
template <typename SolverType, typename OpType>
Results run_eigen_solver(const CustomSparseMatrix &A, int max_restarts, int n_eigvals, int n_bvecs, PerfGroup &pg, rusage &usage_start, rusage &usage_end)
{
	OpType op(A);
	SolverType solver(op, n_eigvals, n_bvecs);

	pg.start();
	getrusage(RUSAGE_SELF, &usage_start);
	double start_time = omp_get_wtime();

	solver.init();
	// We set the tolerance to 0.0 and limit the max iterations to ensure the solver does not exit early due to convergence. For benchmarking
	// purposes, we want to measure a predictable number of iterations without the solver stopping when it finds a "good enough" solution.
	solver.compute(Spectra::SortRule::LargestMagn, max_restarts, 0.0);

	double end_time = omp_get_wtime();
	getrusage(RUSAGE_SELF, &usage_end);
	pg.stop();

	double t_total = end_time - start_time;
	double t_spmv = op.eigensolver_spmv_time;
	double t_mgmt = t_total - t_spmv;

	//.num_iterations() would be the number of restarts.
	//.num_operations() gives the total number of SpMV operations performed.
	return Results{t_spmv, t_mgmt, solver.num_operations()};

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
	std::vector<std::string> args(argv, argv + argc);

	auto it = std::find(args.begin(), args.end(), "--cout");
	bool use_cout = (it != args.end());

	if (argc < 9)
	{
		std::clog << "Usage (File): " << argv[0] << " <matrix.dat> <algo> <arg1> <arg2> <arg3> <run_id> <cores> <numa_policy> <results_csv>\n";
		std::clog << "Usage (Console): " << argv[0] << " <matrix.dat> <algo> <arg1> <arg2> <arg3> <run_id> <cores> <numa_policy> --cout\n";
		return 1;
	}

	std::string matrix_full_path = argv[1];
	std::string algo = argv[2];
	// Linear solvers: Number of iterations ; Eigen solvers: Max number of restarts
	int arg1 = std::stoi(argv[3]);
	// Linear solvers: unused ; Eigen solvers: Number of eigenvalues to compute
	int arg2 = std::stoi(argv[4]);
	// Linear solvers: unused ; Eigen solvers: Number of basis vectors
	int arg3 = std::stoi(argv[5]);

	int run_id = std::stoi(argv[6]);
	int num_cores = std::stoi(argv[7]);
	std::string numa_policy = argv[8];
	std::string results_csv = "";
	if (!use_cout)
	{
		results_csv = argv[9];
	}

	std::string matrix_basename = std::filesystem::path(matrix_full_path).filename().string();

	srand(42);

	CustomSparseMatrix A = load_binary_matrix(matrix_full_path, false);
	Results r;

	PerfGroup pg;
	pg.initialize_std_events();
	struct rusage usage_start, usage_end;

	if (algo == "cg")
	{
		using Solver = Eigen::ConjugateGradient<CustomSparseMatrix, Eigen::Lower | Eigen::Upper, Eigen::IdentityPreconditioner>;
		r = run_linear_solver<Solver>(A, arg1, pg, usage_start, usage_end);
	}
	else if (algo == "bicgstab")
	{
		using Solver = Eigen::BiCGSTAB<CustomSparseMatrix, Eigen::IdentityPreconditioner>;
		// does 2 spmv per iteration
		r = run_linear_solver<Solver>(A, arg1, pg, usage_start, usage_end);
	}
	else if (algo == "lanczos") // IRLM
	{
		using Solver = Spectra::SymEigsSolver<ManualOp>;
		r = run_eigen_solver<Solver, ManualOp>(A, arg1, arg2, arg3, pg, usage_start, usage_end);
	}
	else if (algo == "arnoldi") // IRAM
	{
		using Solver = Spectra::GenEigsSolver<ManualOp>;
		r = run_eigen_solver<Solver, ManualOp>(A, arg1, arg2, arg3, pg, usage_start, usage_end);
	}
	else
	{
		std::cerr << "Unknown algo: " << algo << std::endl;
		return 1;
	}

	std::vector<long long> hw_vals;
	for (auto &e : pg.events)
	{
		hw_vals.push_back(pg.get_value(e.fd));
	}

	long voluntary_switches = usage_end.ru_nvcsw - usage_start.ru_nvcsw;
	long involuntary_switches = usage_end.ru_nivcsw - usage_start.ru_nivcsw;
	long minor_faults = usage_end.ru_minflt - usage_start.ru_minflt;
	long major_faults = usage_end.ru_majflt - usage_start.ru_majflt;
	long peak_rss = usage_end.ru_maxrss;

	std::string result_line = matrix_basename + "," +
							  std::to_string(num_cores) + "," +
							  numa_policy + "," +
							  algo + "," +
							  std::to_string(arg1) + "," +
							  std::to_string(arg2) + "," +
							  std::to_string(arg3) + "," +
							  std::to_string(run_id) + "," +
							  std::to_string(r.spmv_time) + "," +
							  std::to_string(r.mgmt_time) + "," +
							  std::to_string(r.n_ops) + "," +
							  std::to_string(hw_vals[0]) + "," +
							  std::to_string(hw_vals[1]) + "," +
							  std::to_string(hw_vals[2]) + "," +
							  std::to_string(hw_vals[3]) + "," +
							  std::to_string(voluntary_switches) + "," +
							  std::to_string(involuntary_switches) + "," +
							  std::to_string(minor_faults) + "," +
							  std::to_string(major_faults) + "," +
							  std::to_string(peak_rss) + "\n";

	if (use_cout)
	{
		std::cout << result_line;
	}
	else
	{
		std::ofstream stats_file(results_csv, std::ios::app);
		if (stats_file.is_open())
		{
			stats_file << result_line;
			stats_file.close();
		}
		else
		{
			std::cerr << "Error: Could not open results_csv: " << results_csv << "\n";
		}
	}

	return 0;
}