CFLAGS=-c -std=c99 -O3
LIBS=-lm

all: perf test

original: CFLAGS+=-I../original

optimized: CFLAGS+=-I..

original: all

optimized: all

perf: perftest.o
	$(CC) perftest.o $(LIBS) -o perf

perftest.o: perftest.c
	$(CC) $(CFLAGS) -c perftest.c

test: functest.o
	$(CC) functest.o $(LIBS) -o test

functest.o: functest.c
	$(CC) $(CFLAGS) -c functest.c

clean:
	rm -rf *.o perf test

