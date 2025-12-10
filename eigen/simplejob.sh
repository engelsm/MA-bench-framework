#!/bin/bash

module load lang/SciPy-bundle/2024.05-gfbf-2024a
/usr/bin/time -v python lanczos.py > lanczos.out 2> lanczos.time
/usr/bin/time -v python rqi.py > rqi.out 2> rqi.time