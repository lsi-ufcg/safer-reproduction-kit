#!/bin/bash

mkdir -p outputs/stdout
mkdir -p outputs/stderr

cd safer
touch .env
echo "SAFER_ROOT_PATH=$(pwd)" >.env
cd ..

maven_repos=(

)

mkdir -p workstation/maven

MAX_JOBS=2 # adjust based on your CPU/network capability
id=1
job_count=0

run_repo() {
  repo_url="$1"
  id="$2"
  repo_name=$(basename "$repo_url")

  cd workstation/maven
  # git clone --depth 1 "$repo_url.git" "$repo_name"
  group=$(basename "$(dirname "$repo_url")")
  repo=$(basename "$repo_url")
  gh repo fork "$group/$repo" --clone=true
  echo "Waiting for fork to be available..."
  while ! gh repo view "safer-bot/$repo" > /dev/null 2>&1; do
    sleep 2
  done

  echo "Fork available. Proceeding..."
  cd ../../
  ./bash/run-experiment.sh "workstation/maven/$repo_name" "$id" $group/$repo
  rm -rf "workstation/maven/$repo_name"
}

for repo_url in "${maven_repos[@]}"; do
  run_repo "$repo_url" "$id" &
  job_count=$((job_count + 1))
  id=$((id + 1))

  # Wait if max jobs are running
  if ((job_count >= MAX_JOBS)); then
    wait -n # wait for one job to finish
    job_count=$((job_count - 1))
  fi
done

# Gradle
# id=1
# for project_path in workstation/gradle/*; do
#   ./bash/run-experiment.sh $project_path $id
#   id=$(($id + 1))
# done
