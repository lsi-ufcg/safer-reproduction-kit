#!/bin/bash

cd safer
touch .env
echo "SAFER_ROOT_PATH=$(pwd)" > .env

cd ..
for project in workstation/*; do
    echo "Running safer for: $project"
    project_absolute_path=$(pwd)/$project
    cd safer/src
    npx tsx script.ts $project_absolute_path
    cd ../../
    # Coletar os resultados de alguma, criando um CSV para ser utilizado posteriormente no .ipynb
done
