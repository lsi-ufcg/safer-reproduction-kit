#!/bin/bash

project_path=$1
id=$2

project_root_path=$(pwd)/$project_path

project_name=$(basename $project_path)
cd safer/src

start_time=$(date +%s)
PROJECT_ROOT_PATH="$project_root_path" npx tsx script.ts > ../../outputs/output-$project_name.txt
cd ../../

end_time=$(date +%s)
execution_time=$((end_time - start_time))

csv_line=$(cat outputs/output-$project_name.txt | grep -A2 '^CSV:' | tail -n1)

entire_csv_line="$id,$project_name,$csv_line,open source"
echo $entire_csv_line
