# Trabalho 1 - Computacao Paralela - Grupo 20
# Mesmo fonte, mesmas flags de otimizacao: a unica diferenca e o -fopenmp.

CC      = gcc
CFLAGS  = -O2 -Wall -Wextra -std=c11
LDLIBS  = -lm

all: mandelbrot_seq mandelbrot_par

mandelbrot_seq: mandelbrot.c
	$(CC) $(CFLAGS) -o $@ $< $(LDLIBS)

mandelbrot_par: mandelbrot.c
	$(CC) $(CFLAGS) -fopenmp -o $@ $< $(LDLIBS)

# Confere que a versao paralela produz exatamente o mesmo resultado da
# sequencial, comparando o checksum e a imagem gerada.
teste: all
	@echo "== conferindo corretude (checksum e imagem) =="
	@./mandelbrot_seq -w 512 -a 512 -i 500 -o /tmp/seq.pgm
	@OMP_NUM_THREADS=16 ./mandelbrot_par -w 512 -a 512 -i 500 -s dynamic -c 1 -o /tmp/par.pgm
	@cmp /tmp/seq.pgm /tmp/par.pgm && echo "OK: imagens identicas" || echo "FALHOU: imagens diferem"

clean:
	rm -f mandelbrot_seq mandelbrot_par *.pgm

.PHONY: all teste clean
