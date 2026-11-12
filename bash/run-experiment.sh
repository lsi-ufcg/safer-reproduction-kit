#!/bin/bash
#
# Roda o Safer em UM projeto e grava uma linha no dataset.
#
# O Safer novo nao imprime mais a linha "CSV:"; ele grava os resultados numa
# pasta por execucao, cujo caminho sai na linha "Safer run dir:" do stdout. Essa
# pasta vai para outputs/v2/<projeto>/safer-run, e o bash/report-to-csv.py le dela
# a linha do dataset (veja o cabecalho daquele script para as colunas).
#
# Uso: bash/run-experiment.sh <projeto> <id>
#
# Variaveis de ambiente:
#   DATASET_PATH  CSV do dataset (padrao: results/v2/dataset_native_kex.csv)
#   SAFER_CONFIG  config do Safer (padrao: safer-config.json do kit, com
#                 projectTests=true; o padrao do proprio Safer e false)
#
# Saida: 0 quando a linha foi gravada; 1 quando o Safer falhou ou a execucao
# nao pode ser convertida (o motivo fica em results/v2/logs.txt e no terminal).

set -uo pipefail

ROOT_PATH="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SAFER_PATH="$ROOT_PATH/safer"

pretty_print() {
  local DEFAULT="\e[0m" RED="\e[1;31m" YELLOW="\e[1;33m" BLUE="\e[1;34m" GREEN="\e[1;92m"
  local color_uppercase="${1^^}"
  echo -e "${!color_uppercase}${2}${DEFAULT}"
}

absolute() {
  case "$1" in
    /*) echo "$1" ;;
    *)  echo "$ROOT_PATH/$1" ;;
  esac
}

if [ $# -lt 2 ] || [ ! -d "$1" ]; then
  echo "Uso: bash/run-experiment.sh <projeto> <id>" >&2
  exit 1
fi

# O Safer exige caminho absoluto: ele roda a partir de safer/src, e o caminho e
# montado no container com docker -v.
project_path="$(readlink -f "$1")"
id="$2"
dataset_path="$(absolute "${DATASET_PATH:-results/v2/dataset_native_kex.csv}")"
safer_config="$(absolute "${SAFER_CONFIG:-safer-config.json}")"
logs_path="$ROOT_PATH/results/v2/logs.txt"

project_name="$(basename "$project_path")"
# Separadas das saidas do Safer antigo (outputs/<projeto>).
output_dir="$ROOT_PATH/outputs/v2/$project_name"
mkdir -p "$output_dir" "$(dirname "$logs_path")"
rm -rf "$output_dir/safer-run"

echo "Running safer for: $project_path, See outputs/v2/$project_name/stdout.txt"

start_time=$(date +%s)
(
  cd "$SAFER_PATH/src" || exit 1
  PROJECT_ROOT_PATH="$project_path" SAFER_CONFIG="$safer_config" npx tsx script.ts
) > "$output_dir/stdout.txt" 2> "$output_dir/stderr.txt"
safer_status=$?
execution_time=$(( $(date +%s) - start_time ))

# A pasta da execucao fica em safer/.temp/runs ate ser movida; o setup-safer.sh
# apaga a pasta safer inteira.
run_dir=$(sed -n 's/^Safer run dir: //p' "$output_dir/stdout.txt" | tail -1)
if [ -n "$run_dir" ] && [ -d "$run_dir" ]; then
  mv "$run_dir" "$output_dir/safer-run"
  # O id liga a pasta a linha do dataset: com varias execucoes do mesmo projeto,
  # e assim que o pos-processamento acha a pasta de cada linha.
  printf '{ "id": "%s", "dataset": "%s" }\n' "$id" "$dataset_path" > "$output_dir/safer-run/kit.json"
fi

# O pom.xml que o Safer deixa no projeto e o das versoes adotadas.
cp "$project_path/pom.xml" "$output_dir/" 2>/dev/null
commit=$(git -C "$project_path" rev-parse HEAD 2>/dev/null)

failure() {
  pretty_print red "Safer failed to execute in the project $project_name.\n$1" >&2
  echo "[$id] Failure - $project_name." >> "$logs_path"
  exit 1
}

if [ "$safer_status" -ne 0 ]; then
  failure "Safer exited with $safer_status. See outputs/v2/$project_name/stderr.txt"
fi
if [ ! -d "$output_dir/safer-run" ]; then
  failure "No run directory in outputs/v2/$project_name/stdout.txt"
fi

row=$(python3 -I "$ROOT_PATH/bash/report-to-csv.py" \
  --run-dir "$output_dir/safer-run" --output "$dataset_path" --id "$id" --project "$project_name" \
  --execution-time "$execution_time" --artifacts "$commit")
convert_status=$?

if [ "$convert_status" -ne 0 ]; then
  failure "Could not convert outputs/v2/$project_name/safer-run (report-to-csv exited with $convert_status)"
fi

pretty_print green "Safer executed succesfully in the project $project_name.\nSee outputs/v2/$project_name/safer-run/report.md and $dataset_path"

# Coluna 20: Improved. Os nomes de projeto do dataset nao tem virgula.
if [ "$(echo "$row" | cut -d',' -f20)" = "improvement" ]; then
  echo "[$id] Success with improvement - $project_name." >> "$logs_path"
else
  echo "[$id] Success with no improvement - $project_name." >> "$logs_path"
fi
exit 0
