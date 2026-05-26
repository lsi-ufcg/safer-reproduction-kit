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

maven_projects=(
    "/home/sabrina/IDEIA/pesquisa/artigo/todos/evosuite/projects/AgMonk_merge-gf-assets"
)

NUM_INSTANCES=${1:-1}
id=1
job_count=0

run_project() {
  local project_path="$1"
  local id="$2"

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

  local temp_project_path="workstation/maven/${repo_name}"

  echo "[$id] Running project: $project_path"

  rm -rf "$temp_project_path"

  if ! cp -R "$project_path" "$temp_project_path"; then
    echo "Error: Failed to copy project: $project_path"
    echo "[$id] Failure - Copy failed: $project_path" >> "$logs_path"
    return 1
  fi

  echo "[$id] Project copied to: $(realpath "$temp_project_path")"
  echo "[$id] Running safer for: $temp_project_path"
  echo "[$id] See outputs/${repo_name}/stdout.txt"

  if ! ./bash/run-experiment.sh "$temp_project_path" "$id"; then
    echo "[$id] Safer failed to execute in project $repo_name"
    echo "[$id] See outputs/${repo_name}/stderr.txt"
    echo "[$id] Failure - Safer execution failed: $project_path" >> "$logs_path"
    return 1
  fi

  echo "[$id] Success - Finished $project_path"
}

for project_path in "${maven_projects[@]}"; do
  current_id=$id

  run_project "$project_path" "$current_id" &

  job_count=$((job_count + 1))
  id=$((id + 1))

  if (( job_count >= NUM_INSTANCES )); then
    wait -n
    job_count=$((job_count - 1))
  fi
done

wait
echo "Finished all executions."