#define EIGEN_USE_THREADS
#include <omp.h>
#include <Eigen/Core>
#include <Eigen/Sparse>
#include <Spectra/SymEigsSolver.h>
#include <Spectra/GenEigsSolver.h>
#include <Spectra/DavidsonSymEigsSolver.h>
#include <iostream>
#include <string>
#include <chrono>
#include <memory>
#include "util.hpp"

struct ManualOp
{
	using Scalar = ::Scalar;
	const CustomSparseMatrix &m_mat;
	Eigen::VectorXd m_diag; // Diagonale zwischenspeichern
	mutable double eigensolver_spmv_time = 0;
	mutable int true_spmv_count = 0; // Echten Counter hinzufügen

	ManualOp(const CustomSparseMatrix &mat) : m_mat(mat)
	{
		// Diagonale einmal effizient extrahieren (Management Zeit vor dem Loop)
		m_diag = mat.diagonal();
	}

	Scalar operator()(Eigen::Index i, Eigen::Index j) const
	{
		return (i == j) ? m_diag[i] : 0;
	}

	void perform_op(const Scalar *x_in, Scalar *y_out) const
	{
		double start = omp_get_wtime();
		Eigen::Map<const CustomVector> x{x_in, m_mat.cols()};
		Eigen::Map<CustomVector> y{y_out, m_mat.rows()};
		y.noalias() = m_mat * x;
		eigensolver_spmv_time += (omp_get_wtime() - start);
		true_spmv_count++; // Inkrementieren
	}

	template <typename Derived>
	Eigen::Matrix<Scalar, Eigen::Dynamic, Eigen::Dynamic> operator*(const Eigen::MatrixBase<Derived> &block) const
	{
		Eigen::Matrix<Scalar, Eigen::Dynamic, Eigen::Dynamic> res(m_mat.rows(), block.cols());
		for (Eigen::Index i = 0; i < block.cols(); ++i)
		{
			this->perform_op(block.col(i).data(), res.col(i).data());
		}
		return res;
	}
};

template <typename SolverType>
void run_eigen_solver(const CustomSparseMatrix &A, int n_eigvals, int n_bvecs)
{
	ManualOp op(A);
	std::unique_ptr<SolverType> solver;

	if constexpr (std::is_same_v<SolverType, Spectra::DavidsonSymEigsSolver<ManualOp>>)
	{
		int nvec_init = 2 * n_eigvals;
		solver = std::make_unique<SolverType>(op, n_eigvals, nvec_init, n_bvecs);
		// Davidson hat kein .init()
	}
	else
	{
		solver = std::make_unique<SolverType>(op, n_eigvals, n_bvecs);
		solver->init(); // Nur Lanczos/Arnoldi brauchen init()
	}

	auto start_time = std::chrono::high_resolution_clock::now();
	solver->compute(Spectra::SortRule::LargestMagn, 1, 0.0);
	auto end_time = std::chrono::high_resolution_clock::now();

	double t_total = std::chrono::duration<double>(end_time - start_time).count();
	double t_spmv = op.eigensolver_spmv_time;
	double t_mgmt = t_total - t_spmv;

	// Davidson nutzt num_iterations(), Krylow nutzt num_operations()
	int ops = 0;
	if constexpr (std::is_same_v<SolverType, Spectra::DavidsonSymEigsSolver<ManualOp>>)
	{
		ops = solver->num_iterations();
	}
	else
	{
		ops = solver->num_operations();
	}

	std::cout << "EXTRA_DATA," << t_spmv << "," << t_mgmt << "," << ops << std::endl;

	if (solver->info() == Spectra::CompInfo::Successful)
	{
		std::cout << "EVs: " << solver->eigenvalues().transpose() << std::endl;
	}
}

int main(int argc, char **argv)
{
	if (argc < 3)
	{
		std::clog << "Usage: " << argv[0] << " <matrix.dat> <mode> <n_bvecs> <n_eigvals>\n";
		return 1;
	}

	std::string filename = argv[1];
	std::string mode = argv[2];
	int n_bvecs = (argc >= 4) ? std::stoi(argv[3]) : 100;
	int n_eigvals = (argc >= 5) ? std::stoi(argv[4]) : 20;

	CustomSparseMatrix A = load_binary_matrix(filename);

	if (mode == "lanczos")
	{
		run_eigen_solver<Spectra::SymEigsSolver<ManualOp>>(A, n_eigvals, n_bvecs);
	}
	else if (mode == "arnoldi")
	{
		run_eigen_solver<Spectra::GenEigsSolver<ManualOp>>(A, n_eigvals, n_bvecs);
	}
	else if (mode == "davidson")
	{
		run_eigen_solver<Spectra::DavidsonSymEigsSolver<ManualOp>>(A, n_eigvals, n_bvecs);
	}

	return 0;
}