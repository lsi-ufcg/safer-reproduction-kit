#!/bin/bash

pretty_print() {
  local DEFAULT="\e[0m"
  local RED="\e[1;31m"
  local YELLOW="\e[1;33m"
  local BLUE="\e[1;34m"
  local GREEN="\e[1;92m"

  local color_uppercase="${1^^}"
  local message="$2"
  echo -e "${!color_uppercase}${message}${DEFAULT}"
}

dataset_path="results/dataset.csv"
logs_path="results/logs.txt"
project_path=$1
id=$2
relative_module_path=$3
relative_submodule_path=$4

project_root_path=$(pwd)/$project_path

project_name=$(basename $project_path)
echo "Running safer for: $project_path, See outputs/$project_name/stdout.txt"
cd safer/src

start_time=$(date +%s)
mkdir -p ../../outputs/$project_name
PROJECT_ROOT_PATH="$project_root_path" RELATIVE_MODULE_PATH="$relative_module_path" RELATIVE_SUBMODULE_PATH="$relative_submodule_path" npx tsx script.ts >../../outputs/$project_name/stdout.txt 2>../../outputs/$project_name/stderr.txt
cd ../../

end_time=$(date +%s)
execution_time=$((end_time - start_time))

csv_line=$(cat outputs/$project_name/stdout.txt | grep -A2 '^CSV:' | tail -n1)

if [ -z "$csv_line" ]; then
  pretty_print red "Safer failed to execute in the project $project_name.\nSee outputs/$project_name/stderr.txt" >&2
  echo "[$id] Failure - $project_name." >>$logs_path
else
  pretty_print green "Safer executed succesfully in the project $project_name.\nSee outputs/$project_name/stdout.txt and $dataset_path"

  IFS=',' read -r c1 c2 vulnerabilities_before vulnerabilities_after low_before low_after medium_before medium_after high_before high_after critical_before critical_after c13 <<<$csv_line

  current_path=$(pwd)
  cd $project_root_path
  cp pom.xml ../../../outputs/$project_name
  commit=$(git rev-parse HEAD)
  if ((low_after * 1 + medium_after * 2 + high_after * 3 + critical_after * 5 < low_before * 1 + medium_before * 2 + high_before * 3 + critical_before * 5)); then
    entire_csv_line="$id,$project_name,$csv_line,open source,$execution_time,$commit,improvement"
    cd $current_path
    echo "[$id] Success with improvement - $project_name." >>$logs_path
    echo $entire_csv_line >>$dataset_path
  else
    entire_csv_line="$id,$project_name,$csv_line,open source,$execution_time,$commit,no improvement"
    cd $current_path
    echo "[$id] Success with no improvement - $project_name." >>$logs_path
    echo $entire_csv_line >>$dataset_path
  fi
fi
