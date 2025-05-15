#!/bin/bash

mkdir -p outputs/stdout
mkdir -p outputs/stderr

cd safer
touch .env
echo "SAFER_ROOT_PATH=$(pwd)" > .env

cd ..
id=1  
for project_path in workstation/*; do
    echo "Running safer for: $project_path"
    ./bash/run-experiment.sh $project_path $id
    id=$(($id + 1))
done
