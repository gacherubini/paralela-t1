#!/usr/bin/env bash
#SBATCH --job-name=mandel-g20
#SBATCH --partition=LAD_geral
#SBATCH --nodes=1
#SBATCH --exclusive
#SBATCH --output=resultados/slurm-%j.out
#
# --exclusive e o que mais importa aqui: sem ele outro grupo pode estar rodando
# no mesmo no e os tempos ficam sem sentido para calcular speed-up.
#
# submeter:  sbatch job.sh
# olhar:     squeue -u $USER   /   tail -f resultados/slurm-*.out

set -euo pipefail
cd "$SLURM_SUBMIT_DIR"

echo "no: $(hostname)"
nproc
make clean && make
./medir.sh
./analisar.sh
