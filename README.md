# Safer Reproduction Kit

Safer is an application designed to identify and mitigate vulnerabilities in software dependencies by evaluating the compatibility of their versions with a given project. This tool aims to enhance project security through detailed analysis and flexible configuration.

Here's a detailed step-by-step on how to reproduce the experiments presented in the Safer paper.

## Prerequisites

To run Safer, ensure you have the following installed:

-   Node.js version 16.16.0 or higher
-   npm version 8.11.0 or higher
-   Docker version 26.1.1 or higher

## Setup and Installation

Unzip Safer and install its dependencies

```bash
./setup-safer.sh
```

## Run Experiments

If you don't want to run the experiments for all projects open this bash script and comment the projects you don't want to run  
Sudo privileges are required to delete the repository directory after Safer execution  

```bash
sudo ./run-experiments.sh
```

## Results

The dataset of the experiments is saved as `results/dataset.csv`.  
You can execute the `analysis.ipynb` notebook to visualize result charts from the dataset

# Creating Issues and PRs

`gh config set git_protocol ssh`

`./fork-test-repositories.sh`

`./run-experiments.sh`

`./create-github-artifacts.sh`
