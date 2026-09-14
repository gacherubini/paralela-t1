#!/usr/bin/env bash
# Complemento HT: acrescenta SOMENTE o ponto de 16 threads aos CSVs que o
# job.sh principal ja gerou. Nao reescreve nada, so anexa linhas no mesmo
# formato (mediana de REPS) e reimprime as tabelas.
#
# O --nodelist prende ao mesmo no do run principal para o ponto HT ser
# comparavel. Se ficar pendente (PD) por muito tempo, apague essa linha e
# ressubmeta: outro no equivalente serve, desde que anotado no relatorio.
#SBATCH --job-name=mandel-g20-ht
#SBATCH --nodes=1
#SBATCH --exclusive
#SBATCH --output=slurm-ht-%j.out
#SBATCH --nodelist=atlantica05
#
# submeter (no atlantica, dentro do repo):  sbatch ht.sh
# acompanhar:  squeue -u $USER

set -euo pipefail
cd "$SLURM_SUBMIT_DIR"

export OMP_PLACES=cores
export OMP_PROC_BIND=close

REPS=3; ITER=2000; LADO=4096

# Mesma mediana do medir.sh: roda REPS vezes e guarda a do meio.
mediana() {
    local saidas=()
    local i
    for ((i = 0; i < REPS; i++)); do
        saidas+=("$("$@")")
    done
    printf '%s\n' "${saidas[@]}" | sort -t';' -k8 -g | sed -n "$(( (REPS + 1) / 2 ))p"
}

echo "no: $(hostname)"
make

# Forte: os 3 escalonadores com 16 threads (2 por nucleo fisico = HT).
for combo in "static 0" "dynamic 1" "guided 0"; do
    set -- $combo
    echo -n "forte $1 chunk=$2 16 threads ... "
    mediana env OMP_NUM_THREADS=16 ./mandelbrot_par \
        -w "$LADO" -a "$LADO" -i "$ITER" \
        -s "$1" -c "$2" | tee -a resultados/forte.csv | cut -d';' -f8
done

# Fraca: 1024*sqrt(16) = 4096 de lado, mesmo sched padrao do medir.sh.
echo -n "fraca 16 threads (4096x4096) ... "
mediana env OMP_NUM_THREADS=16 ./mandelbrot_par \
    -w 4096 -a 4096 -i "$ITER" -s dynamic -c 1 \
    | tee -a resultados/fraca.csv | cut -d';' -f8

./analisar.sh | tee resultados/tabelas.txt
