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

project_base_path=$(pwd)/workstation
dataset=results/dataset.csv

# Read the Dataset
tail -n +2 $dataset | while IFS=',' read -r c1 project_name c3 c4 c5 c6 c7 c8 c9 c10 c11 c12 c13 c14 type c16; do
  pretty_print blue "Creating github artifacts for $project_name"
  project_root_path=$project_base_path/$type/$project_name

  file=""
  if [ "$type" == "maven" ]; then
    file="pom.xml"
  elif [ "$type" == "gradle" ]; then
    file="build.gradle"
  else
    echo "Unknown project type" >&2
    continue
  fi

  ./bash/commit-dependencies-file.sh $project_root_path $file
  ./bash/submit-artifacts-github.sh $project_root_path $(pwd)/outputs/stdout/$project_name.txt

done
