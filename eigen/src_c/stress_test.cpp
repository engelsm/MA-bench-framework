#include <Eigen/Dense>
#include <iostream>
#include <omp.h>
#include <chrono>

int main(int argc, char **argv)
{
	// 1. Thread-Check
	int max_threads = omp_get_max_threads();
	// Eigen::setNbThreads(max_threads); // Sicherstellen, dass Eigen alle nutzt

	std::cout << "Pruefe Skalierung mit " << max_threads << " Threads." << std::endl;

	// 2. Workload Groesse definieren
	// Eine 5000x5000 Matrix braucht ca. 200MB RAM, aber Trillionen an FLOPs
	int size = 5000;
	if (argc > 1)
		size = std::stoi(argv[1]);

	std::cout << "Generiere Matrizen der Groesse " << size << "x" << size << "..." << std::endl;

	Eigen::MatrixXd A = Eigen::MatrixXd::Random(size, size);
	Eigen::MatrixXd B = Eigen::MatrixXd::Random(size, size);
	Eigen::MatrixXd C;

	std::cout << "Berechne C = A * B (das sollte skalieren)..." << std::endl;

	// Zeitmessung
	auto start = std::chrono::high_resolution_clock::now();

	// Der eigentliche Workload (Matrix-Multiplikation ist O(n^3))
	C = A * B;

	auto end = std::chrono::high_resolution_clock::now();
	std::chrono::duration<double> elapsed = end - start;

	std::cout << "Dauer: " << elapsed.count() << " Sekunden." << std::endl;
	std::cout << "Pruefsumme: " << C.sum() << std::endl; // Verhindert, dass Compiler wegbaeckelt

	return 0;
}