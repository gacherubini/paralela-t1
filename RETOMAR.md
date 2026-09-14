# Trabalho 1 — Mandelbrot com OpenMP — Grupo 20

Repositório compartilhado: https://github.com/gacherubini/paralela-t1
Conta LAD: `cp32020` · atlantica.lad.pucrs.br

## Arquivos

| Arquivo | O que é |
|---|---|
| `mandelbrot.c` | Fonte único. Sem `-fopenmp` vira a versão sequencial; com, a paralela. |
| `Makefile` | `make` gera os dois binários; `make teste` confere que as imagens batem. |
| `medir.sh` | Coleta os tempos → `resultados/{forte,fraca,sched}.csv`. Detecta os núcleos do nó. |
| `analisar.sh` | Lê os CSVs e imprime as tabelas com speed-up e eficiência. |
| `job.sh` | Submissão ao Slurm: `sbatch job.sh`. Roda make + medir + analisar. |
| `ht.sh` | Complemento HT: anexa só o ponto 16 threads aos CSVs (`sbatch ht.sh`). |
| `graficos.py` | Gera os gráficos de escalabilidade (PDF vetorial + PNG). |
| `relatorio/relatorio.tex` | Esqueleto no formato exigido. TODOs marcam cada seção. |

## Como rodar no cluster

```bash
# 1. do seu login pessoal na sparta:
ssh cp32020@atlantica.lad.pucrs.br

# 2. clonar (ou dar git pull se já existir)
git clone https://github.com/gacherubini/paralela-t1 && cd paralela-t1

# 3. conferir que compila e que o paralelo bate com o sequencial
make teste

# 4. submeter (NÃO rodar na atlantica; o sbatch aloca um nó)
sbatch job.sh
squeue -u $USER          # acompanhar
tail -f slurm-*.out      # ver saindo

# 5. ao terminar, as tabelas ficam em resultados/tabelas.txt
```

Se o `sbatch` reclamar de partição, rode `sinfo`, veja o nome na coluna
PARTITION e descomente a linha `--partition` no `job.sh`.

## O que falta

- [x] Rodar o `sbatch job.sh` no cluster e trazer `resultados/` (13/set, nó
      atlantica05, 2x Xeon E5520 = 8 núcleos físicos / 16 threads, gcc 9.4.0).
- [x] Ponto HT: `sbatch ht.sh` no mesmo nó (dynamic 16t: S=12,07, E=75,4%).
- [x] Nomes dos integrantes no cabeçalho (Gabriel Coelho, Gabriel Cherubini).
- [x] Gráficos: a planilha do professor não foi encontrada, então `graficos.py`
      gera os dois exigidos (forte e fraca), cada um com speed-up e eficiência
      e a linha do ideal para comparação. Gerados em 13/set (`python graficos.py resultados`).
- [ ] Preencher as tabelas, escrever a análise e gerar o PDF.

## Correções aplicadas sobre a primeira versão

1. **Não compilava.** `-std=c11` é ISO estrito e esconde os símbolos POSIX:
   `CLOCK_MONOTONIC` e `optarg` ficavam indefinidos. Corrigido com
   `-std=gnu11` no Makefile **e** `#define _POSIX_C_SOURCE 200809L` no fonte,
   para compilar sob qualquer `-std` (inclusive o comando do enunciado).
2. **`THREADS` fixo em `1 2 4 8 16`.** Agora `medir.sh` descobre os núcleos
   físicos do nó e monta a escada até o total. O enunciado pede explicitamente
   a máquina com o maior número de núcleos possível.
3. **`job.sh` morria antes de iniciar.** O `--output=resultados/slurm-%j.out`
   aponta para um diretório que o Slurm ainda não tem — ele abre o arquivo de
   saída antes de o script rodar, e `resultados/` só é criado dentro do script.
4. **Partição `LAD_geral` não verificada.** Comentada: sem `--partition` o
   Slurm usa a fila padrão. Conferir com `sinfo` antes de fixar um nome.
5. `job.sh` agora salva `resultados/maquina.txt` (CPU, memória, gcc) — o
   relatório precisa identificar onde as medições foram feitas.
6. **Escalabilidade forte media só `dynamic`.** Agora varre `static`,
   `dynamic,1` e `guided` ao longo de toda a escada de threads. Sem isso o
   gráfico teria uma linha só e o efeito do desbalanceamento — o motivo de ter
   escolhido o Mandelbrot — ficaria invisível. No teste local com 4 threads:
   `static` 52,5% de eficiência contra 93,3% do `dynamic`.

## Decisões de projeto para citar no relatório

- **Por que Mandelbrot:** pixels independentes, mas custo por pixel variando em
  até três ordens de grandeza (dentro do conjunto gasta sempre `max_iter`).
  O desbalanceamento é real e justifica a comparação de escalonadores da rubrica.
- **Laço de linhas**, não de colunas nem `collapse(2)`: granularidade grossa e
  cada thread escreve em faixa própria da imagem, sem falso compartilhamento.
- **`schedule(runtime)` + `omp_set_schedule`** pela linha de comando: compara
  escalonadores com o binário idêntico, sem recompilar.
- **`reduction(+:checksum)`**: evita o `atomic` no laço interno, que serializaria.
- **Escalabilidade fraca por `sqrt(p)`** sobre a *mesma* janela do plano:
  preserva o custo médio por pixel. Ampliar a região em vez da resolução
  mudaria a natureza do trabalho e falsearia o resultado.
- **`OMP_PROC_BIND=close` / `OMP_PLACES=cores`**: sem migração de threads e sem
  hyper-threads, que achatariam o speed-up.
- **Mediana de 3**, não média: uma execução contaminada distorce a média.
- **Checksum idêntico** entre sequencial e paralelo, em toda contagem de
  threads, mais `cmp` das imagens: é a prova de corretude.

## Gráficos

`python3 graficos.py [dir]` lê `resultados/{forte,fraca}.csv` e gera
`grafico_forte.pdf` e `grafico_fraca.pdf` (mais PNGs para conferir na tela).
O `relatorio.tex` já inclui os PDFs — vetoriais, não perdem qualidade.

Cada figura tem dois painéis, speed-up e eficiência, em eixos separados de
propósito: as duas grandezas têm escalas diferentes e sobrepô-las num eixo duplo
é o erro clássico de gráfico. A linha tracejada cinza é o ideal ($S(p)=p$ na
forte, tempo constante na fraca).

Precisa de matplotlib: `pip install matplotlib`. Se o nó do cluster não tiver,
o `job.sh` avisa e segue — é só rodar o script na máquina local depois.
