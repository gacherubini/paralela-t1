# T1 Paralela — Mandelbrot OpenMP (Grupo 20, cp32020)

## 1. Acesso ao LAD

Servidor: `atlantica.lad.pucrs.br`

De casa / Wi-Fi (credencial de aluno — primeira parte do e-mail PUCRS + senha do e-mail):

```bash
ssh <usuario>@sparta.pucrs.br
# dentro da sparta:
ssh cp32020@atlantica.lad.pucrs.br
```

De dentro da PUCRS ou da sparta (credencial do grupo):

```bash
ssh cp32020@atlantica.lad.pucrs.br
```

Troca de senha (só funciona logado na atlantica a partir de dentro da PUCRS):

```bash
yppasswd
```

Suporte: `suporte.lad@pucrs.br`
Conta `cp32000` é do professor. Dados de uso podem ser usados em pesquisa (confidencial, não nominal).

> Não commitar senha no repo. A senha inicial está no Moodle; troque com `yppasswd` assim que possível.

## 2. Projeto

`mandelbrot.c` único gera as duas versões (sem `-fopenmp` os pragmas são ignorados):

```bash
make                    # gera mandelbrot_seq e mandelbrot_par
make teste              # confere checksum + imagem seq vs par (16 threads, dynamic,1)
```

Opções: `-w largura -a altura -i max_iter -t threads -s static|dynamic|guided -c chunk -o saida.pgm`
Saída stdout é CSV: `modo;threads;schedule;chunk;largura;altura;max_iter;tempo;checksum`.
Checksum igual entre seq e par = prova de corretude.

## 3. Medição na atlantica (8 cores / 16 threads)

```bash
sbatch job.sh            # job --exclusive na partição LAD_geral, roda make + medir.sh + analisar.sh
squeue -u $USER
tail -f resultados/slurm-*.out
```

O que cada script faz:

- `medir.sh` — gera `resultados/forte.csv` (problema fixo, threads 1..16, T1 do binário seq real),
  `resultados/fraca.csv` (pixels crescem com p, lado = base*sqrt(p)) e `resultados/sched.csv`
  (static/dynamic/guided x chunks). Cada ponto = mediana de `REPS=3`. Fixa `OMP_PLACES=cores`, `OMP_PROC_BIND=close`.
- `analisar.sh` — imprime tabelas com speed-up e eficiência + confere checksum.
  Forte: `S(p)=Tseq/T(p)`, `E(p)=S(p)/p`. Fraca: `E(p)=Tseq/T(p)`.
- Vars ajustáveis: `THREADS`, `REPS`, `ITER`, `LADO`, `LADO_BASE`, `SCHED_FORTE`, `CHUNK_FORTE`.

## 4. Relatório (1 PDF)

- p1: cabeçalho reduzido + texto em coluna dupla, margens ~1cm, fonte 10.
- p2: tabelas tempos + speed-up + eficiência (forte e fraca), coluna simples + gráficos da planilha fornecida.
- p3+: código fonte formatado, coluna simples, sem limite (colar do VS Code preserva formato; ou Overleaf).

Rubrica: T1 seq local (1 core) como referência; versão par OpenMP; tempos par local;
speed-up + eficiência forte e fraca; gráficos da planilha; descrever problema e eixos de paralelização;
quais diretivas, onde e otimizações; analisar resultados (explicar, não repetir);
balanceamento + escalonadores/chunks; código claro; participação nos acompanhamentos e na apresentação.
