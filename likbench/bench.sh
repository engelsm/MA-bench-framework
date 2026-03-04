#!/bin/bash

# ml perf/likwid/5.3.0-GCC-13.2.0
MODE="SME96"         
NUMA_SET="default" 

BENCHMARKS="peakflops triad copy_mem"
SIZES="20MB 1GB"

echo "Mode,NUMA,Bench,Size,CPUs,Run,MBps"

for bench in $BENCHMARKS; do
    for size in $SIZES; do
        for cores in 8 24 48 72 96; do
            for run in {1..3}; do
                
                # MB/s extrahieren
                RES=$(likwid-bench -t $bench -w N:$size:$cores 2>/dev/null | grep "MByte/s" | awk '{print $2}')
                
                echo "$MODE,$NUMA_SET,$bench,$size,$cores,$run,$RES"
            done
        done
    done
done