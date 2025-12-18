#define EIGEN_USE_THREADS
#include <omp.h>
#include <Eigen/Core>
#include <Eigen/Sparse>
#include <Spectra/SymEigsSolver.h>
#include <Spectra/MatOp/SparseSymMatProd.h>
#include <iostream>
#include <string>
#include "load_binary_matrix.h"

// We use rowMajor for parallelization as colMajor causes write conflicts with multiple threads slowing down the computation
struct ManualParallelOp
{
	using Scalar = double;

	// Explizite Angabe des Typs aus dem Eigen-Namensraum
	const Eigen::SparseMatrix<double, Eigen::RowMajor> &m_mat;

	ManualParallelOp(const Eigen::SparseMatrix<double, Eigen::RowMajor> &mat) : m_mat(mat) {}

	Eigen::Index rows() const { return (int)m_mat.rows(); }
	int cols() const { return (int)m_mat.cols(); }

	void perform_op(const double *x_in, double *y_out) const
	{
		// Eigen::Map erlaubt es, auf rohe Pointer wie auf Eigen-Objekte zuzugreifen
		Eigen::Map<const Eigen::VectorXd> x(x_in, m_mat.cols());
		Eigen::Map<Eigen::VectorXd> y(y_out, m_mat.rows());

#pragma omp parallel for
		for (int i = 0; i < (int)m_mat.outerSize(); ++i)
		{
			double sum = 0;
			// InnerIterator ist spezifisch für das Speicherlayout der SparseMatrix
			for (Eigen::SparseMatrix<double, Eigen::RowMajor>::InnerIterator it(m_mat, i); it; ++it)
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

	int max_threads = omp_get_max_threads();

	// Eigen-interne Parallelisierung initialisieren
	Eigen::initParallel();
	Eigen::setNbThreads(max_threads);
	std::cout << "Erzwinge Parallelisierung auf " << max_threads << " Threads." << std::endl;

	// Laden der Matrix mit explizitem Typ
	Eigen::SparseMatrix<double, Eigen::RowMajor> A = load_binary_matrix(argv[1]);

	ManualParallelOp op(A);

	// Spectra-Solver benötigt den Operator-Typ als Template-Parameter
	Spectra::SymEigsSolver<ManualParallelOp> solver(op, 2, 20);
	solver.init();
	solver.compute();

	if (solver.info() == Spectra::CompInfo::Successful)
	{
		std::cout << "Eigenwerte: " << solver.eigenvalues().transpose() << std::endl;
	}
	else
	{
		std::cerr << "Solver konnte nicht konvergieren." << std::endl;
	}

	return 0;
}