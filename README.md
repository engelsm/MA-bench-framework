# MA-bench-framework

A lightweight benchmarking tool designed to automate reproducible performance runs on HPC systems. It aims to abstract the layers between workloads, configuration input, and execution as much as possible. Benchmarks, resource settings, and compiler flags are defined through a really simple YAML file. The tool then handles compilation, resource configuration, execution, performance tracking and SLURM job script generation. The framework is developed with security environments like AMD SEV in mind.

Status: Work in progress. Core features, code structure and this README are still under development.

Notes:
Setup for AMDuProf: download tar, unpack, set env, ... (possibly turn into script) 