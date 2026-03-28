#include <omp.h>
#include <Eigen/Core>
#include <Eigen/Sparse>
#include <iostream>
#include <fstream>
#include <vector>
#include <chrono>
#include <numeric>
#include <filesystem>
#include <sys/resource.h>
#include <cstdint>
#include "util.hpp"
#include "util_perf.hpp"

struct IterData
{
	double elapsed;
	double gflops;
};

int main(int argc, char **argv)
{
	std::vector<std::string> args(argv, argv + argc);

	// The --cout flag is used for debugging purposes.
	auto it = std::find(args.begin(), args.end(), "--cout");
	bool use_cout = (it != args.end());

	if (argc < 8)
	{
		std::cerr << "Usage (File): " << argv[0] << " <matrix.bin> <iterations> <NUMA_opt 0/1> <run_id> <cores> <numa_policy> <results_csv> <iter_csv>\n";
		std::cerr << "Usage (Console): " << argv[0] << " <matrix.bin> <iterations> <NUMA_opt 0/1> <run_id> <cores> <numa_policy> --cout\n";
		return 1;
	}

	std::string matrix_full_path = args[1];
	int max_iterations = std::stoi(args[2]);
	bool NUMA_optimize = (std::stoi(args[3]) != 0);
	int run_id = std::stoi(args[4]);
	int num_cores = std::stoi(args[5]);
	std::string numa_policy = args[6];

	std::string results_csv = "";
	std::string iter_csv = "";
	if (!use_cout)
	{
		results_csv = args[7];
		iter_csv = args[8];
	}

	std::string matrix_basename = std::filesystem::path(matrix_full_path).filename().string();

	srand(42);
	omp_set_num_threads(num_cores);

	// IO is measured with std::chrono to get the actual whole time spent, including all overheads in non-user mode.
	auto io_start = std::chrono::high_resolution_clock::now();
	CustomSparseMatrix A = load_binary_matrix(matrix_full_path, NUMA_optimize);
	auto io_end = std::chrono::high_resolution_clock::now();
	double io_elapsed = std::chrono::duration<double>(io_end - io_start).count();

	CustomVector x(A.cols());
	CustomVector y(A.rows());

	if (NUMA_optimize)
	{
#pragma omp parallel for schedule(static)
		for (int i = 0; i < A.rows(); i++)
			y[i] = 0.0;
#pragma omp parallel for schedule(static)
		for (int i = 0; i < A.cols(); i++)
			x[i] = static_cast<Scalar>(rand()) / RAND_MAX;
	}
	else
	{
		y.setZero();
		x.setRandom();
	}

	auto *row_ptr = A.outerIndexPtr();
	auto *col_idx = A.innerIndexPtr();
	auto *values = A.valuePtr();

	std::vector<IterData> iter_results;
	iter_results.reserve(max_iterations);

	PerfGroup pg;
	pg.initialize_std_events();

	struct rusage usage_start, usage_end;

	pg.start();

	getrusage(RUSAGE_SELF, &usage_start);

	for (int iter = 0; iter < max_iterations; ++iter)
	{
		double t_start = omp_get_wtime();
		spmv_csr(A.rows(), row_ptr, col_idx, values, x, y);
		double t_end = omp_get_wtime();
		double elapsed = t_end - t_start;
		iter_results.push_back({elapsed, calculate_gflops(A.nonZeros(), elapsed)});
	}

	getrusage(RUSAGE_SELF, &usage_end);

	pg.stop();

	double total_spmv_time = 0;
	for (const auto &res : iter_results)
		total_spmv_time += res.elapsed;
	double avg_gflops = calculate_gflops(A.nonZeros(), total_spmv_time);

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
							  std::to_string(run_id) + "," +
							  std::to_string(max_iterations) + "," +
							  std::to_string(io_elapsed) + "," +
							  std::to_string(total_spmv_time) + "," +
							  std::to_string(avg_gflops) + "," +
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

	if (!use_cout && !iter_csv.empty())
	{
		std::ofstream iter_file(iter_csv, std::ios::app);
		if (iter_file.is_open())
		{
			for (size_t i = 0; i < iter_results.size(); ++i)
			{
				iter_file << run_id << ","
						  << (i + 1) << ","
						  << iter_results[i].elapsed << ","
						  << iter_results[i].gflops << "\n";
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