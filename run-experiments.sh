#!/bin/bash

CSV_FILE="results.csv"
echo "id,Project Name,Number of Dependencies Analyzed,Number of Dependencies with Vulnerabilities,Number of dependencies with vulnerabilities (Before),Number of dependencies with vulnerabilities (After),Number of vulnerabilities (Before),Number of vulnerabilities (After),Low vulnerabilities (Before),Low vulnerabilities (After),Medium vulnerabilities (Before),Medium vulnerabilities (After),High vulnerabilities (Before),High vulnerabilities (After),Critical vulnerabilities (Before),Critical vulnerabilities (After),Execution Time (s),Build Tool,Project Type" > $CSV_FILE

mkdir -p outputs

cd safer
touch .env
echo "SAFER_ROOT_PATH=$(pwd)" > .env

cd ..
id=1  
for project_path in workstation/*; do
    echo "Running safer for: $project_path"
    csv_line=$(./bash/run-experiment.sh $project_path $id)
    echo $csv_line >> $CSV_FILE
    id=$(($id + 1))
done
