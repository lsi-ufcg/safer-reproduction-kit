# Calculate Offset Changes

For each dependency, this script calculates the distance between the current version to the version applied by Safer and the distance between the veresion applied by Safer and the newest version of the dependency.

It receives `results/dataset.csv` as input and outputs `./dataset-version-changes.csv`

## How to run

Install dependencies  
`npm i`

Run script  
`node src/script.js`
