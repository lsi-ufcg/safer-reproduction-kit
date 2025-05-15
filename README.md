# Safer Reproduction Kit

Safer is an application designed to identify and mitigate vulnerabilities in software dependencies by evaluating the compatibility of their versions with a given project. This tool aims to enhance project security through detailed analysis and flexible configuration.

Here's a detailed step-by-step on how to reproduce the experiments presented in the Safer paper.

## Prerequisites

To run Safer, ensure you have the following installed:

-   Node.js version 16.16.0 or higher
-   npm version 8.11.0 or higher
-   Docker version 26.1.1 or higher

## Setup and Installation

To set up the project locally, follow these steps:

### 1. Unzip Safer

```bash
unzip safer.zip
```

### 2. Install required dependencies

```bash
cd safer
npm install
cd ..
```

## Clone Test Repositories

```bash
./clone-test-repositories.sh
```

## Run Experiments

```bash
./run-experiments.sh
```

## Results

The results of our experiments can be found in the `results/analysis.ipynb` directory
