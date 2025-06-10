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

project_root_path=$(pwd)/$project_path

project_name=$(basename $project_path)
echo "Running safer for: $project_path, See outputs/stdout/$project_name.txt"
cd safer/src

start_time=$(date +%s)
output=$(PROJECT_ROOT_PATH="$project_root_path" npx tsx script.ts | tee /dev/tty)
cd ../../

end_time=$(date +%s)
execution_time=$((end_time - start_time))

csv_line=$(echo "$output" | grep -A2 '^CSV:' | tail -n1)

if [ -z "$csv_line" ]; then
  pretty_print red "Safer failed to execute in the project $project_name.\nSee outputs/stderr/$project_name.txt" >&2
  echo "Safer failed to execute in the project $project_name." >> $logs_path
  echo ""
else
  entire_csv_line="$id,$project_name,$csv_line,open source,$execution_time"
  echo $entire_csv_line >> $dataset_path
  pretty_print green "Safer executed succesfully in the project $project_name.\nSee outputs/stdout/$project_name.txt and $dataset_path"
  echo ""
fi
