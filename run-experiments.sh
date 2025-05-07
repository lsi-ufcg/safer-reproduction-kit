#!/bin/bash

CSV_FILE="results.csv"
echo "id,Project Name,Number of Dependencies Analyzed,Number of Dependencies with Vulnerabilities,Number of dependencies with vulnerabilities (Before),Number of dependencies with vulnerabilities (After),Number of vulnerabilities (Before),Number of vulnerabilities (After),Low vulnerabilities (Before),Low vulnerabilities (After),Medium vulnerabilities (Before),Medium vulnerabilities (After),High vulnerabilities (Before),High vulnerabilities (After),Critical vulnerabilities (Before),Critical vulnerabilities (After),Execution Time (s),Build Tool,Project Type" > $CSV_FILE

cd safer
touch .env
echo "SAFER_ROOT_PATH=$(pwd)" > .env

cd ..
id=1  
for project in workstation/*; do
    echo "Running safer for: $project"
    project_absolute_path=$(pwd)/$project
    cd safer/src

    start_time=$(date +%s)
    output=$(npx tsx script.ts "$project_absolute_path")

    cd ../../

    # Coletar os resultados de alguma, criando um CSV para ser utilizado posteriormente no .ipynb
    before_deps=$(echo "$output" | grep "Before: " | head -n1 | awk '{print $3}')
    after_deps=$(echo "$output" | grep "After: " | head -n1 | awk '{print $5}')

    before_vuln=$(echo "$output" | grep "Number of vulnerabilities:" -A 1 | grep "Before" | awk '{print $4}')
    after_vuln=$(echo "$output" | grep "Number of vulnerabilities:" -A 2 | grep "After" | awk '{print $4}')

    low_before=$(echo "$output" | grep "Before execution" | awk -F'Low: ' '{print $2}' | awk -F',' '{print $1}')
    low_after=$(echo "$output" | grep "After execution" | awk -F'Low: ' '{print $2}' | awk -F',' '{print $1}')

    medium_before=$(echo "$output" | grep "Before execution" | awk -F'Medium: ' '{print $2}' | awk -F',' '{print $1}')
    medium_after=$(echo "$output" | grep "After execution" | awk -F'Medium: ' '{print $2}' | awk -F',' '{print $1}')

    high_before=$(echo "$output" | grep "Before execution" | awk -F'High: ' '{print $2}' | awk -F',' '{print $1}')
    high_after=$(echo "$output" | grep "After execution" | awk -F'High: ' '{print $2}' | awk -F',' '{print $1}')

    critical_before=$(echo "$output" | grep "Before execution" | awk -F'Critical: ' '{print $2}')
    critical_after=$(echo "$output" | grep "After execution" | awk -F'Critical: ' '{print $2}')

    # Código só para teste - APAGAR DEPOIS
    before_deps=${before_deps:-"N/A"}
    after_deps=${after_deps:-"N/A"}
    before_vuln=${before_vuln:-"0"}
    after_vuln=${after_vuln:-"0"}
    low_before=${low_before:-"0"}
    low_after=${low_after:-"0"}
    medium_before=${medium_before:-"0"}
    medium_after=${medium_after:-"0"}
    high_before=${high_before:-"0"}
    high_after=${high_after:-"0"}
    critical_before=${critical_before:-"0"}
    critical_after=${critical_after:-"0"}

     # Exibe todos os valores no terminal - APAGAR DEPOIS
    echo "Dependencies with vulnerabilities (Before): $before_deps"
    echo "Dependencies with vulnerabilities (After):  $after_deps"
    echo "Vulnerabilities (Before): $before_vuln"
    echo "Vulnerabilities (After):  $after_vuln"
    echo "Low (Before): $low_before | Low (After): $low_after"
    echo "Medium (Before): $medium_before | Medium (After): $medium_after"
    echo "High (Before): $high_before | High (After): $high_after"
    echo "Critical (Before): $critical_before | Critical (After): $critical_after"

    #AJUSTAR 
    end_time=$(date +%s)
    execution_time=$((end_time - start_time))

    if [ -f "$project/build.gradle" ]; then
        build_tool="gradlew"
    elif [ -f "$project/pom.xml" ]; then
        build_tool="maven"
    else
        build_tool="unknown"
    fi

    project_name=$(basename "$project")
    echo "A$id,$project_name,0,0,$before_deps,$after_deps,$before_vuln,$after_vuln,$low_before,$low_after,$medium_before,$medium_after,$high_before,$high_after,$critical_before,$critical_after,$execution_time,$build_tool,open source" >> $CSV_FILE

    id=$((id + 1))
done
