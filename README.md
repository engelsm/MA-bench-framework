# amd-secure-bench

A lightweight benchmarking tool designed to automate reproducible performance runs on HPC systems. It aims to abstract the layers between workloads, configuration input, and execution as much as possible. Benchmarks, resource settings, and compiler flags are defined through a really simple YAML file. The tool then handles compilation, resource configuration, execution, performance tracking and SLURM job script generation. The framework is developed with AMD's security environments in mind and supports running benchmarks across different security modes.

Status: Work in progress. Core features and code structure are still under development.