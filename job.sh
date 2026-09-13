#!/usr/bin/env bash
#SBATCH --job-name=mandel-g20
#SBATCH --nodes=1
#SBATCH --exclusive
#SBATCH --output=slurm-%j.out
#
# --exclusive e o que mais importa aqui: sem ele outro grupo pode estar rodando
# no mesmo no e os tempos ficam sem sentido para calcular speed-up.
#
# PARTICAO: sem --partition o Slurm usa a fila padrao do cluster, que e o que
# queremos na duvida. Para escolher outra, rode "sinfo" no atlantica, veja o
# nome correto na coluna PARTITION e descomente a linha abaixo com esse nome:
##SBATCH --partition=NOME_DA_PARTICAO
#
# A saida vai para slurm-<id>.out na raiz do projeto, e nao para resultados/:
# o Slurm abre esse arquivo no instante em que o job comeca, ANTES do script
# rodar, entao apontar para um diretorio que ainda nao existe faz o job morrer
# sem nem iniciar.
#
# submeter:  sbatch job.sh
# olhar:     squeue -u $USER   /   tail -f slurm-*.out

set -euo pipefail
cd "$SLURM_SUBMIT_DIR"

echo "no: $(hostname)"
echo "nproc: $(nproc)"
LC_ALL=C lscpu | sed -n 's/^Model name: *//p' | head -1

# Guarda a descricao da maquina: o relatorio precisa identificar onde mediu.
mkdir -p resultados
{ hostname; LC_ALL=C lscpu; free -g; gcc --version | head -1; } > resultados/maquina.txt 2>&1

make clean && make
./medir.sh
./analisar.sh | tee resultados/tabelas.txt
