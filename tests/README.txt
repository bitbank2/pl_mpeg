Functional and performance tests for pl_mpeg.

The makefile has two targets: original and optimized

These will build the identical test programs from
either the original source code or the new, optimized code. e.g.

make original
make optimized

The output of the makefile is two programs: perf & test
These programs expect a single parameter of a MPEG-1 file.

'perf' runs the decoder as video-only and video+audio and throws
away the output. The total decode time is displayed in milliseconds.

'test' runs the decoder and displays CRC32 values for each frame's
Y, Cb and Cr planes. These can then be compared to the original
output to ensure that no changes have been introduced.

