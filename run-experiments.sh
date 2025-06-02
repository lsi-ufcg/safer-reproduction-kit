#!/bin/bash

mkdir -p outputs/stdout
mkdir -p outputs/stderr

cd safer
touch .env
echo "SAFER_ROOT_PATH=$(pwd)" >.env
cd ..

# Maven
id=1
for project_path in workstation/maven/*; do
  ./bash/run-experiment.sh $project_path $id
  id=$(($id + 1))
done

# Gradle
# id=1
# for project_path in workstation/gradle/*; do
#   ./bash/run-experiment.sh $project_path $id
#   id=$(($id + 1))
# done
