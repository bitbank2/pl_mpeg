Functional and performance tests for pl_mpeg. The makefile has two targets-
original and optimized. These will build the identical test programs from
either the original source code or the new, optimized code. e.g.

make original
make optimized

The two programs generated (perf test) are testing performance and
correctness. These expect a single parameter of a MPEG-1 file passed on the
command line. They will each print the test results to STDOUT.

