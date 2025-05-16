#!/bin/bash

project_path=$1
dependencies_file=$2

cd $project_path
main_branch=$(git rev-parse --abbrev-ref HEAD)
git checkout safer-result || git checkout -b safer-result

git add $dependencies_file

git commit -m "add new $dependencies_file updated by Safer"
git push -u origin safer-result
git checkout $main_branch

# Usage: ./bash/commit-dependencies-file.sh /home/cristovao/codes/playground/github-cli-playground pom.xml
