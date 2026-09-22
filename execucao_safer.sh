#!/bin/bash

set -u

# Uma instancia por vez. Cada execucao comeca apagando workstation/maven, e os
# projetos compartilham o nome do container (java-container-safer-<projeto>):
# duas instancias apagam os projetos e os containers uma da outra, e o Safer
# falha com "No such container" mesmo quando os testes estao verdes.
mkdir -p workstation
exec 200>"workstation/.execucao_safer.lock"
if ! flock -n 200; then
  echo "Erro: o execucao_safer.sh ja esta rodando (veja: pgrep -af execucao_safer.sh)." >&2
  exit 1
fi

mkdir -p outputs
mkdir -p results
mkdir -p workstation/maven

cd safer || exit 1
touch .env
echo "SAFER_ROOT_PATH=$(pwd)" > .env
cd .. || exit 1

logs_path="results/logs.txt"
touch "$logs_path"

# Configuracao local da maquina (caminhos, combinacao). Fica fora do git para
# que ninguem precise editar um arquivo versionado para rodar o experimento.
# Veja experiment.env.example.
# shellcheck source=/dev/null
[ -f experiment.env ] && . ./experiment.env

# Diretorio com os projetos e os testes gerados (a entrada do experimento) e
# diretorio onde cada projeto e copiado para ser executado.
source_dir="${SOURCE_DIR:-$PWD/../analise-geracao-testes/projects}"
dest_dir="${DEST_DIR:-$PWD/workstation/maven}"

if [ ! -d "$source_dir" ]; then
  echo "Erro: diretorio de origem nao encontrado: $source_dir" >&2
  echo "Defina SOURCE_DIR em experiment.env (veja experiment.env.example)." >&2
  exit 1
fi

# Combinacao de testes desta execucao: as categorias que serao executadas, entre
# native, evosuite e kex. E a unica coisa a mudar para rodar outra combinacao --
# ela define o que arrange_tests monta em cada copia e o nome dos tres arquivos
# de resultado.
COMBINATION="${COMBINATION:-native,kex}"

combination_slug="$(echo "$COMBINATION" | tr -d ' ' | tr ',' '_')"

run_native=false
run_evosuite=false
run_kex=false
for category in $(echo "$COMBINATION" | tr ',' ' '); do
  case "$category" in
    native)   run_native=true ;;
    evosuite) run_evosuite=true ;;
    kex)      run_kex=true ;;
    *) echo "Erro: categoria desconhecida em COMBINATION: $category" >&2; exit 1 ;;
  esac
done

# Resultados do Safer nesta combinacao, coluna 2 = Project Name. Sao executados
# todos os projetos de $source_dir que tenham testes nativos em src/test/java e
# que ainda nao aparecam nesse arquivo, o que permite retomar a execucao de onde
# parou. Se o arquivo nao existir, nada e pulado.
completed_csv="results/dataset_${combination_slug}.csv"

# O bash/run-experiment.sh grava os resultados do Safer nesse mesmo arquivo.
export DATASET_PATH="$completed_csv"

# Suites apagadas pelo filtro, uma linha por projeto, com o mesmo id do dataset.
filter_csv="results/deleted-tests_${combination_slug}.csv"

echo "Combinacao: $COMBINATION"
echo "Origem: $source_dir"
echo "Resultados: $completed_csv e $filter_csv"

# Número de execuções por projeto
EXECUTIONS_PER_PROJECT=${2:-1}
NUM_INSTANCES=${1:-1}
id=1
job_count=0
MAX_PROJECTS=10

# Função que verifica se o projeto possui testes nativos em src/test/java
has_native_tests() {
  local project_path="$1"

  find "$project_path" \
    -type d \( -name target -o -name evosuite-tests -o -name kex-tests \) -prune -o \
    -type f -name '*.java' -path '*/src/test/java/*' -print -quit \
    2>/dev/null | grep -q .
}

# Monta, na copia do projeto, exatamente as suites da combinacao em execucao.
#
# As geradas entram como subdiretorio de src/test/java (src/test/java/kex-tests,
# src/test/java/evosuite-tests): e assim que o run-maven-build.sh do Safer
# reconhece que ha testes gerados e injeta as dependencias que eles precisam. As
# categorias de fora sao removidas desta copia -- a origem nunca e alterada.
arrange_tests() {
  local project_path="$1"

  if $run_native; then
    :
  elif [ -d "${project_path}/src/test/java" ]; then
    echo "Removendo testes nativos de src/test/java..."
    find "${project_path}/src/test/java" -mindepth 1 -delete
  fi

  for category in evosuite kex; do
    local origin="${project_path}/${category}-tests"
    [ -d "$origin" ] || continue

    if ! eval "\$run_${category}"; then
      echo "Removendo ${category}-tests..."
      rm -rf "$origin"
      continue
    fi

    echo "Movendo ${category}-tests para src/test/java..."
    mkdir -p "${project_path}/src/test/java"
    mv "$origin" "${project_path}/src/test/java/"
  done
}


# Carrega os projetos que já foram executados nesta combinação
declare -A completed_projects=()

load_completed_projects() {
  local csv_path="$1"

  if [ ! -f "$csv_path" ]; then
    echo "Aviso: arquivo de execuções concluídas não encontrado: $csv_path"
    echo "Nenhum projeto será pulado por já ter sido executado."
    return 0
  fi

  local name
  while IFS= read -r name; do
    [ -z "$name" ] && continue
    completed_projects["$name"]=1
  done < <(awk -F',' 'NR > 1 { gsub(/\r/, "", $2); if ($2 != "") print $2 }' "$csv_path")
}

is_completed_project() {
  local project_name="$1"
  [ -n "${completed_projects[$project_name]:-}" ]
}

# Função para resetar o projeto ao estado original
reset_project() {
  local project_path="$1"
  local original_source="$2"
  local project_name="$3"
  
  echo "Resetando projeto: $project_name"
  
  # Remove o projeto atual
  rm -rf "$project_path"
  
  # Copia novamente do original
  if cp -R "${original_source}/${project_name}" "$project_path"; then
    echo "✓ Projeto resetado: $project_name"
    return 0
  else
    echo "✗ Erro ao resetar projeto: $project_name"
    return 1
  fi
}

run_project() {
  local project_path="$1"
  local id="$2"
  local execution_num="$3"

  if [ -z "$project_path" ]; then
    echo "Error: Empty project path"
    echo "[$id] Failure - Empty project path" >> "$logs_path"
    return 1
  fi

  if [ ! -d "$project_path" ]; then
    echo "Error: Project path does not exist: $project_path"
    echo "[$id] Failure - Path not found: $project_path" >> "$logs_path"
    return 1
  fi

  local repo_name
  repo_name=$(basename "$project_path")

  echo "[$id] Running project: $project_path (Execution $execution_num of $EXECUTIONS_PER_PROJECT)"
  echo "[$id] See outputs/${repo_name}/execution_${execution_num}/stdout.txt"

  mkdir -p "outputs/${repo_name}/execution_${execution_num}"

  # A combinacao vem de $COMBINATION; veja arrange_tests.
  arrange_tests "$project_path"

  # =============================================
  # PRIMEIRO: Filtra as suites que falham
  # =============================================
  # Roda sobre o projeto ja no layout da combinacao acima, com o mesmo build e o
  # mesmo JDK do Safer, e apaga desta copia as suites que quebram a build ou
  # falham. O Safer roda em seguida mesmo que o filtro nao chegue ao verde; o
  # status de cada projeto fica em $filter_csv.
  echo "[$id] Filtrando suites que falham..."
  ./run-test-filtering.sh -o "$filter_csv" --id "$id" \
    --logs-dir "outputs/${repo_name}/execution_${execution_num}/test-filtering" \
    "$project_path"

  # =============================================
  # SEGUNDO: Executa o SAFER
  # =============================================
  echo "[$id] Executando SAFER após mover os testes..."
  echo "[$id] Running safer for: $project_path"
  
  ./bash/run-experiment.sh "$project_path" "$id" "$execution_num"
  safer_status=$?

  echo "[$id] run-experiment.sh terminou com código $safer_status"

  # Move stdout/stderr se existirem
  if [ -f "outputs/${repo_name}/stdout.txt" ]; then
    mv "outputs/${repo_name}/stdout.txt" \
       "outputs/${repo_name}/execution_${execution_num}/"
  fi

  if [ -f "outputs/${repo_name}/stderr.txt" ]; then
    mv "outputs/${repo_name}/stderr.txt" \
       "outputs/${repo_name}/execution_${execution_num}/"
  fi

  if [ "$safer_status" -ne 0 ]; then
      echo "[$id] Safer failed to execute in project $repo_name (Execution $execution_num)"
      echo "[$id] Failure - Safer execution failed: $project_path (Execution $execution_num)" >> "$logs_path"
      return "$safer_status"
  fi

  echo "[$id] Success - Finished $project_path (Execution $execution_num)"
  return 0
}

load_completed_projects "$completed_csv"
echo "Projetos já executados em $completed_csv: ${#completed_projects[@]}"

echo "Copiando projetos com testes nativos ainda não executados de $source_dir para $dest_dir"

mkdir -p "$dest_dir"

# Limpa destino anterior
rm -rf "${dest_dir:?}"/*

# Copia apenas os projetos que possuem testes nativos em src/test/java e que
# ainda não foram executados nesta combinação
skipped_count=0
copied_count=0
already_done_count=0

for project_path in "$source_dir"/*; do
  if [ -d "$project_path" ]; then
    project_name=$(basename "$project_path")

    if is_completed_project "$project_name"; then
      echo "- Ignorado (já executado em $completed_csv): $project_name"
      already_done_count=$((already_done_count + 1))
      continue
    fi

    if ! has_native_tests "$project_path"; then
      echo "- Ignorado (sem testes nativos em src/test/java): $project_name"
      echo "[skip] No native tests in src/test/java: $project_name" >> "$logs_path"
      skipped_count=$((skipped_count + 1))
      continue
    fi

    echo "Copiando $project_name"

    if cp -R "$project_path" "$dest_dir/"; then
      echo "✓ Projeto copiado: $project_name"
      copied_count=$((copied_count + 1))
    else
      echo "✗ Erro ao copiar projeto: $project_name"
    fi
  fi
done

echo "Projetos copiados: $copied_count"
echo "Projetos ignorados (sem testes nativos): $skipped_count"
echo "Projetos ignorados (já executados): $already_done_count"

# Avisa sobre projetos já executados que não foram encontrados em $source_dir,
# o que indica divergência entre o CSV de resultados e o diretório de origem
missing_count=0
for project_name in "${!completed_projects[@]}"; do
  if [ ! -d "$source_dir/$project_name" ]; then
    echo "! Projeto em $completed_csv mas ausente de $source_dir: $project_name"
    echo "[warn] In $completed_csv but missing from source: $project_name" >> "$logs_path"
    missing_count=$((missing_count + 1))
  fi
done
echo "Projetos já executados e ausentes da origem: $missing_count"

# Descobre todos os projetos copiados
maven_projects=()
for project_path in "$dest_dir"/*; do
  if [ -d "$project_path" ]; then
    maven_projects+=("$project_path")
  fi
done

if [ ${#maven_projects[@]} -eq 0 ]; then
  echo "Nenhum projeto pendente encontrado em $source_dir"
  echo "(todos já estão em $completed_csv ou não têm testes nativos)"
  exit 0
fi

echo "Encontrados ${#maven_projects[@]} projetos para processar"
echo "Cada projeto será executado $EXECUTIONS_PER_PROJECT vezes"
echo "Total de execuções: $((${#maven_projects[@]} * EXECUTIONS_PER_PROJECT))"

# Para cada projeto
for project_path in "${maven_projects[@]}"; do
  repo_name=$(basename "$project_path")
  
  # Executar o projeto N vezes
  for execution_num in $(seq 1 $EXECUTIONS_PER_PROJECT); do
    current_id=$id
    
    echo "========================================="
    echo "Iniciando execução $execution_num de $EXECUTIONS_PER_PROJECT para $repo_name"
    echo "========================================="
    
    # Executar o projeto
    run_project "$project_path" "$current_id" "$execution_num"
    
    # Resetar o projeto para o estado original após cada execução (exceto na última)
    if [ $execution_num -lt $EXECUTIONS_PER_PROJECT ]; then
      echo "Resetando projeto para próxima execução..."
      if ! reset_project "$project_path" "$source_dir" "$repo_name"; then
        echo "Erro ao resetar projeto. Abortando execuções para $repo_name"
        break
      fi
    fi
    
    id=$((id + 1))
    
  done
  
  echo "========================================="
  echo "Finalizadas todas as $EXECUTIONS_PER_PROJECT execuções para $repo_name"
  echo "========================================="
  
done

wait
echo "Finished all executions."
echo "Total de execuções realizadas: $((id - 1))"