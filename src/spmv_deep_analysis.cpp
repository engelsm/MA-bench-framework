#include <omp.h>
#include <Eigen/Core>
#include <Eigen/Sparse>
#include <iostream>
#include <fstream>
#include <vector>
#include <chrono>
#include <numeric>
#include <filesystem>
#include "util.hpp"
#include "util_perf.hpp"

std::string results_file_name = "results.csv";
std::string iter_file_name = "iter.csv";

/**
 * Perform Sparse Matrix-Vector Multiplication (SpMV) using CSR format
 * https://en.wikipedia.org/wiki/Sparse_matrix#Compressed_sparse_row_(CSR,_CRS_or_Yale_format)
 */
void spmv_csr(int rows, const int *row_ptr, const int *col_idx, const Scalar *values, const CustomVector &x, CustomVector &y)
{
// Parallelize over rows
#pragma omp parallel for schedule(static)
	for (int i = 0; i < rows; i++)
	{
		Scalar sum = 0;
		for (int j = row_ptr[i]; j < row_ptr[i + 1]; j++)
			sum += values[j] * x[col_idx[j]];
		y[i] = sum;
	}
}

int main(int argc, char **argv)
{
	if (argc < 7)
	{
		std::cerr << "Usage: " << argv[0] << " <matrix.bin> <iterations> <NUMA_opt 0/1> <run_id> <cores> <output_dir>\n";
		return 1;
	}

	std::string matrix_full_path = argv[1];
	int max_iterations = std::stoi(argv[2]);
	bool NUMA_optimize = (std::stoi(argv[3]) != 0);
	int run_id = std::stoi(argv[4]);
	int num_cores = std::stoi(argv[5]);
	std::string output_dir = argv[6];

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

	struct IterData
	{
		double elapsed;
		double gflops;
	};
	std::vector<IterData> iter_results;
	iter_results.reserve(max_iterations);

	PerfGroup pg;
	// Events are defined in perf_event.h by the Linux kernel
	pg.add_event(PERF_TYPE_HARDWARE, PERF_COUNT_HW_CPU_CYCLES, "cycles");
	pg.add_event(PERF_TYPE_HARDWARE, PERF_COUNT_HW_INSTRUCTIONS, "instructions");
	pg.add_event(PERF_TYPE_HARDWARE, PERF_COUNT_HW_CACHE_MISSES, "cache_misses");
	// https://stackoverflow.com/questions/61190033/how-to-measure-the-dtlb-hits-and-dtlb-misses-with-perf-event-open
	pg.add_event(PERF_TYPE_HW_CACHE, (PERF_COUNT_HW_CACHE_DTLB | (PERF_COUNT_HW_CACHE_OP_READ << 8) | (PERF_COUNT_HW_CACHE_RESULT_MISS << 16)), "dtlb_load_misses");

	pg.start();
	for (int iter = 0; iter < max_iterations; ++iter)
	{
		double t_start = omp_get_wtime();
		spmv_csr(A.rows(), row_ptr, col_idx, values, x, y);
		double t_end = omp_get_wtime();
		double elapsed = t_end - t_start;
		iter_results.push_back({elapsed, (2.0 * A.nonZeros()) / (elapsed * 1e9)});
	}
	pg.stop();

	double total_spmv_time = 0;
	for (const auto &res : iter_results)
		total_spmv_time += res.elapsed;
	double avg_gflops = (2.0 * A.nonZeros() * max_iterations) / (total_spmv_time * 1e9);

	std::vector<long long> hw_vals;
	for (auto &e : pg.events)
	{
		hw_vals.push_back(pg.get_value(e.fd));
	}

	// Write aggregated statistics
	std::string results_file_path = output_dir + "/" + results_file_name;
	std::ofstream stats_file(results_file_path, std::ios::app);
	if (stats_file.is_open())
	{
		stats_file << matrix_basename << ","
				   << num_cores << ","
				   << run_id << ","
				   << max_iterations << ","
				   << io_elapsed << ","
				   << total_spmv_time << ","
				   << avg_gflops << ","
				   << hw_vals[0] << ","
				   << hw_vals[1] << ","
				   << hw_vals[2] << ","
				   << hw_vals[3] << "\n";
		stats_file.close();
	}

	// Write detailed iteration results
	std::string iter_file_path = output_dir + "/" + iter_file_name;
	std::ofstream iter_file(iter_file_path, std::ios::app);

	if (iter_file.is_open())
	{
		for (size_t i = 0; i < iter_results.size(); ++i)
		{
			iter_file << run_id << ","
					  << i + 1 << ","
					  << iter_results[i].elapsed << ","
					  << iter_results[i].gflops << "\n";
		}
		iter_file.close();
	}

	return 0;
}