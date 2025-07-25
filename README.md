# Safer Reproduction Kit

Here's a detailed step-by-step on how to reproduce the experiments presented in the ICSE 2026 Safer paper.

> OBS: The experiments were conducted on PopOS 22.04 Operating System, which is based on Ubuntu. We cannot ensure the behavior of this Reproduction Kit for others Linux versions

## Prerequisites

To run Safer, ensure you have the following installed:

-   Node.js version 22.16.0
-   Docker
-   Maven 3.6.3

You can use our bash scripts if you are using Ubuntu-based distros and haven't installed the Prerequisites

```bash
./bash/ubuntu/install-node.sh
nvm use 22.16.0
./bash/ubuntu/install-docker.sh
./bash/ubuntu/install-maven.sh
```

## Safer's Setup and Installation

Unzip Safer and install its dependencies

```bash
./setup-safer.sh
```

## Run Experiments

In `run-experiments.sh` script, we have the full list of 35187 github open-source projects as of June 2025  
You can choose what projects you want to run Safer by changing this list

You can run Safer in multiple projects in parallel. For that, pass the number of instances as an argument to the script  
We recommend a number of instances between 2 and 6

```bash
./run-experiments.sh <num_instances>
```

If you want to run only the projects Safer execution succeeded and at the commit hash Safer runned. You should use `run-only-successful-experiments.sh`  

```bash
./run-only-successful-experiments.sh
```

### Monitorint the Experiment Execution

As the Experiment proceeds, some files are modified

#### Current Executions

The current projects are cloned in `workstation/maven` folder  
You can see the projects safer is being executed by using `docker ps` and looking for containers named as `java-container-safer-*`

#### Experiment Progress

You can see the experiment progress in `results/logs.txt` file

"Failure" means Safer could not be executed in the project. You can see Safer stderr logs in `outputs/<project_name>/stderr.txt`

"Success with no improvement" means Safer executed but could not improve the security of the project, therefore the `pom.xml` file was not changed. You can see the Safer logs in `outputs/<project_name>/stdout.txt` and vulnerabilities information in `results/dataset.csv`

"Success with improvement" means Safer executed and reduced vulnerabilities, modifying `pom.xml` file. You can see the Safer logs in `outputs/<project_name>/stdout.txt`, the vulnerabilities reduction in `results/dataset.csv` and the new `pom.xml` file in `outputs/<project_name>/pom.xml`

## Post Processing

After we finished the experiments and started to analyse the results, we needed to collect more data to complement our analysis. We extracted these extra data from Safer logs in `outputs/<project_name>/stdout.txt`. The scripts used for this step are stored in `post-processing` folder and described below:

### Count Version Changes script

We used this script to count the sum of update categories according to Semantic Versioning.  
The data collected was used to plot "Figure 8: Distribution of update categories introduced by Safer." graph.  
You can find this script and how to execute it in `post-processing/count-version-changes/README.md`

### Calculate Offset Changes script

We used this script to calculate the distance between the current version to the version applied by Safer and the distance between the veresion applied by Safer and the newest version of the dependency.  
The data collected was used to answer "RQ4: Are the automatic suggestions of Safer more compatible with the project’s current state than other tools such as Dependabot?" and display "Table 2: Dependencies of the WepSpa by OWASP"  
You can find this script and how to execute it in `post-processing/calculate-offset-changes/README.md`

## Results

After Post Processing step, we have two final datasets

-   `results/final-dataset.csv`
-   `post-processing/calculate-offset-changes/dataset-version-changes.csv`

To generate the charts we used in the paper, we used Jupyter notebooks

The `results/analysis.ipynb` notebook consumes `results/final-dataset.csv`  
The `results/analysis-rq4.ipynb` notebook consumes `post-processing/calculate-offset-changes/dataset-version-changes.csv`

You can find instructions and how to execute the notebooks in `results/notebooks/README.md`

# Creating Issues and PRs

We also tried to create issues and Pull Requests with the results produced by Safer, however, our account got flagged in the middle of the process.  
In one day, we opened 1791 Pull Requests, and 15 were accepted

The logs of this execution can be found in `results/artifacts.log`  
The bash script we used is `create-github-artifacts.sh`

We're trying to contact Github to recover our account and continue the contribution for the 7139 projects improved by Safer.

`eval "$(ssh-agent -s)"`  
`ssh-add -D`  
`ssh-add ~/.ssh/github-safer-bot`  
`./create-github-artifacts.sh`

## Github Search

The list of 35187 projects from Github was obtained using `github-search` script. You can find more details in `github-search/README.md`
