# Count Version Changes

This script counts the sum of changes types, according to Semver

## Columns

It adds the following columns to the dataset: javaVersion, countMajor, countMinor, countPatch, countPrerelease, countBuildmetadata

The javaVersion column retrieves the Java Version of the project  
The countMajor column counts the amount of major updates Safer applied  
The countMinor column counts the amount of minor updates Safer applied  
The countPatch column counts the amount of patch updates Safer applied  
The countPrerelease column counts the amount of pre-release updates Safer applied  
The countBuildmetadata column counts the amount of build metadata updates Safer applied

It receives `results/dataset.csv` and `outputs/<project_name>/stdout.txt` as inputs and outputs `results/final-dataset.csv` and `./output.txt` log file

## How to Run

Install dependencies  
`npm i`

Run script  
`node src/script.js`
