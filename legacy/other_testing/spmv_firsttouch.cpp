#define EIGEN_USE_THREADS
#include <omp.h>
#include <Eigen/Core>
#include <Eigen/Sparse>
#include <iostream>
#include <vector>
#include <chrono>
#include <random>
#include "util.hpp"

int main(int argc, char **argv)
{
	if (argc < 3)
	{
		std::cerr << "Usage: " << argv[0] << " <matrix.bin> <iterations>\n";
		return 1;
	}
	std::srand(42);

	// Matrix laden (Passiert meist sequentiell auf einem Kern)
	CustomSparseMatrix m_mat = load_binary_matrix(argv[1]);
	int iterations = std::stoi(argv[2]);

	// Vektoren ohne Initialisierung anlegen
	CustomVector x(m_mat.cols());
	CustomVector y(m_mat.rows());

	// --- FIRST TOUCH INITIALISIERUNG ---
	// Wir nutzen das gleiche Scheduling wie im Benchmark-Loop.
	// Das zwingt Linux, die Memory-Pages in den L3/RAM des jeweiligen CCDs zu legen.

#pragma omp parallel
	{
// Jeder Thread initialisiert "seinen" Teil des Vektors x
#pragma omp for schedule(static)
		for (Eigen::Index i = 0; i < x.size(); ++i)
		{
			x(i) = static_cast<Scalar>(i % 100) / 10.0;
		}

// Jeder Thread initialisiert "seinen" Teil des Ergebnisvektors y
#pragma omp for schedule(static)
		for (Eigen::Index i = 0; i < y.size(); ++i)
		{
			y(i) = 0.0;
		}

// Optional: Die Matrix-Werte einmal "anfassen", um sie lokal zu binden
// Da wir nur lesend zugreifen, hilft das dem Prefetcher
#pragma omp for schedule(static)
		for (Eigen::Index i = 0; i < m_mat.outerSize(); ++i)
		{
			volatile Scalar dummy = 0;
			for (CustomSparseMatrix::InnerIterator it(m_mat, i); it; ++it)
			{
				dummy += it.value();
			}
		}
	}

	// --- BENCHMARK LOOP ---
	// Kein Warmup hier, da wir 'perf stat' von außen für den gesamten Prozess nutzen.
	// Die Kosten für das initiale Laden der SEV-Pages werden so mitgemessen.

	auto start = std::chrono::high_resolution_clock::now();

	for (int iter = 0; iter < iterations; ++iter)
	{
// schedule(static) ist kritisch, damit die Datenlokalität vom First-Touch erhalten bleibt
#pragma omp parallel for schedule(static)
		for (Eigen::Index i = 0; i < m_mat.outerSize(); ++i)
		{
			Scalar sum = 0;
			for (CustomSparseMatrix::InnerIterator it(m_mat, i); it; ++it)
			{
				sum += it.value() * x(it.col());
			}
			y(i) = sum;
		}
	}

	auto end = std::chrono::high_resolution_clock::now();
	std::chrono::duration<double> elapsed = end - start;

	// Berechnung der GFLOPS (2 * NNZ pro Iteration)
	double gflops = (2.0 * m_mat.nonZeros() * iterations) / (elapsed.count() * 1e9);

	std::cout << "EXTRA_DATA,"
			  << elapsed.count() << ","
			  << gflops << std::endl;

	return 0;
}