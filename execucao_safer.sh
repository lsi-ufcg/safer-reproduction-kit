#!/bin/bash

set -u

mkdir -p outputs
mkdir -p results
mkdir -p workstation/maven

cd safer || exit 1
touch .env
echo "SAFER_ROOT_PATH=$(pwd)" > .env
cd .. || exit 1

logs_path="results/logs.txt"
touch "$logs_path"

# Diretório de origem dos projetos
source_dir="/home/suelenfelix/TCC/teste/gitlab/analise-geracao-testes" # Ajuste para o seu path
# Diretório de destino
dest_dir="/home/suelenfelix/TCC/teste/safer-reproduction-kit/workstation/maven" # Ajuste para o seu path

# Número de execuções por projeto
EXECUTIONS_PER_PROJECT=${2:-1}
NUM_INSTANCES=${1:-1}
id=1
job_count=0
MAX_PROJECTS=10

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

  # Neste ponto é onde o código deve ser ajustado para executar a combinação desejada.
  # Abaixo, temos a combinação que irá executar todos os testes.

  if [ -d "${project_path}/src/test" ]; then
      # echo "[$id] Removendo src/test..."
      rm -rf "${project_path}/evosuite-tests" # Apaga conteudo de evosuite-tests
      rm -rf "${project_path}/kex-tests" # Apaga conteudo de kex-tests
      rm -rf "${project_path}/src/test/java"/* # Remove todo o conteúdo de src/test/java

      # Intrucoes para mover testes evosuite para a pasta de testes a ser executadas
    #   if [ -d "${project_path}/evosuite-tests" ]; then
    #     echo "Movendo evosuite-tests para src/test..."

    #     mkdir -p "${project_path}/src/test"
        
    #     mv "${project_path}/evosuite-tests" "${project_path}/src/test/java"
    # fi

    # # Intrucoes para mover testes kex para a pasta de testes a ser executadas
    # if [ -d "${project_path}/kex-tests" ]; then
    #   echo "Limpando src/test/java..."

    #   mkdir -p "${project_path}/src/test/java"

    #   echo "Movendo kex-tests para src/test/java..."

    #   mv "${project_path}/kex-tests" "${project_path}/src/test/java/"
    # fi
  fi

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

echo "Copiando todos os projetos de $source_dir para $dest_dir"

mkdir -p "$dest_dir"

# Limpa destino anterior
rm -rf "${dest_dir:?}"/*

# Copia todos os projetos
for project_path in "$source_dir"/*; do
  if [ -d "$project_path" ]; then
    project_name=$(basename "$project_path")

    echo "Copiando $project_name"

    if cp -R "$project_path" "$dest_dir/"; then
      echo "✓ Projeto copiado: $project_name"
    else
      echo "✗ Erro ao copiar projeto: $project_name"
    fi
  fi
done

# Descobre todos os projetos copiados
maven_projects=()
for project_path in "$dest_dir"/*; do
  if [ -d "$project_path" ]; then
    maven_projects+=("$project_path")
  fi
done

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