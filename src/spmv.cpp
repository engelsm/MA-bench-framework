/**
 * @brief Runs an SpMV benchmark, collects timing and hardware counter metrics, and writes results to CSV or stdout.
 *
 * This entry point parses command-line arguments, loads a sparse matrix from a binary file,
 * initializes vectors, executes CSR-based sparse matrix-vector multiplication for a configured
 * number of iterations, and records:
 * - Matrix I/O load time
 * - Per-iteration execution times
 * - Total SpMV time
 * - Selected hardware performance counter values
 *
 * Output modes:
 * - File mode: appends summary metrics to `results_csv` and per-iteration timings to `iter_csv`
 * - Console mode (`--cout`): prints only the summary result line to standard output (debugging purpose)
 *
 * @param argv Command-line argument array.
 * Expected arguments:
 * - File mode:
 *   `<matrix.bin> <iterations> <run_id> <cores> <process_numa_policy> <results_csv> <iter_csv>`
 * - Console mode:
 *   `<matrix.bin> <iterations> <run_id> <cores> <process_numa_policy> --cout`
 *
 * @return 0 on success, 1 when arguments are invalid.
 */

#include <omp.h>
#include <Eigen/Core>
#include <Eigen/Sparse>
#include <iostream>
#include <fstream>
#include <vector>
#include <chrono>
#include <numeric>
#include <filesystem>
#include <cstdint>
#include "util.hpp"
#include "util_perf.hpp"
int main(int argc, char **argv)
{
	std::vector<std::string> args(argv, argv + argc);

	auto it = std::find(args.begin(), args.end(), "--cout");
	bool use_cout = (it != args.end());

	if (argc < 8)
	{
		std::cerr << "Usage (File): " << argv[0] << " <matrix.bin> <iterations> <run_id> <cores> <process_numa_policy> <results_csv> <iter_csv>\n";
		std::cerr << "Usage (Console): " << argv[0] << " <matrix.bin> <iterations> <run_id> <cores> <process_numa_policy> --cout\n";
		return 1;
	}

	std::string matrix_full_path = args[1];
	int max_iterations = std::stoi(args[2]);
	int run_id = std::stoi(args[3]);
	int num_cores = std::stoi(args[4]);
	std::string process_numa_policy = args[5];

	std::string results_csv = "";
	std::string iter_csv = "";
	if (!use_cout)
	{
		results_csv = args[6];
		iter_csv = args[7];
	}

	std::string matrix_basename = std::filesystem::path(matrix_full_path).filename().string();

	srand(42);
	omp_set_num_threads(num_cores);

	auto io_start = std::chrono::high_resolution_clock::now();
	CustomSparseMatrix A = load_binary_matrix(matrix_full_path);
	auto io_end = std::chrono::high_resolution_clock::now();
	double io_elapsed = std::chrono::duration<double>(io_end - io_start).count();

	CustomVector x(A.cols());
	CustomVector y(A.rows());

	y.setZero();
	x.setRandom();

	auto *row_ptr = A.outerIndexPtr();
	auto *col_idx = A.innerIndexPtr();
	auto *values = A.valuePtr();

	std::vector<double> iter_times(max_iterations);

	PerfGroup pg;
	pg.initialize_std_events();
	pg.start();

	for (int iter = 0; iter < max_iterations; ++iter)
	{
		double t_start = omp_get_wtime();
		spmv_csr(A.rows(), row_ptr, col_idx, values, x, y);
		double t_end = omp_get_wtime();
		double elapsed = t_end - t_start;
		iter_times[iter] = elapsed;
	}

	pg.stop();

	double total_spmv_time = 0;
	for (const auto &res : iter_times)
	{
		total_spmv_time += res;
	}

	std::vector<long long> hw_vals;
	for (auto &e : pg.events)
	{
		hw_vals.push_back(pg.get_value(e.fd));
	}

	std::string result_line = matrix_basename + "," +
							  std::to_string(num_cores) + "," +
							  process_numa_policy + "," +
							  std::to_string(run_id) + "," +
							  std::to_string(max_iterations) + "," +
							  std::to_string(io_elapsed) + "," +
							  std::to_string(total_spmv_time) + "," +
							  std::to_string(hw_vals[0]) + "," +
							  std::to_string(hw_vals[1]) + "," +
							  std::to_string(hw_vals[2]) + "," +
							  std::to_string(hw_vals[3]) + "\n";

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

	if (!use_cout && !iter_csv.empty())
	{
		std::ofstream iter_file(iter_csv, std::ios::app);
		if (iter_file.is_open())
		{
			for (size_t i = 0; i < iter_times.size(); ++i)
			{
				iter_file << run_id << "," << (i + 1) << "," << iter_times[i] << "\n";
			}
			iter_file.close();
		}
		else
		{
			std::cerr << "Error: Could not open iter_csv: " << iter_csv << "\n";
		}
	}

	return 0;
}