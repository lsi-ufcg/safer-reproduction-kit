#!/bin/bash

dataset_path="results/dataset.csv"

mkdir -p outputs

cd safer
touch .env
echo "SAFER_ROOT_PATH=$(pwd)" > .env

cd ..
id=1  
for project_path in workstation/*; do
    echo "Running safer for: $project_path"
    csv_line=$(./bash/run-experiment.sh $project_path $id)
    echo $csv_line >> $dataset_path
    id=$(($id + 1))
done
