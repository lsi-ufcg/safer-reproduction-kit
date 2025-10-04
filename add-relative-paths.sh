#!/usr/bin/env bash

while read -r name path; do
  # remove leading ./ and trailing /pom.xml
  clean_path="${path#./}"
  clean_path="${clean_path%/pom.xml}"

  # root module = first folder
  root="${clean_path%%/*}"

  # path from root to submodule (remove the root part)
  sub_path="${clean_path#"$root/"}"

  # compute relative path from submodule to root
  # count how many levels deep the submodule is
  depth=$(grep -o "/" <<< "$sub_path" | wc -l)
  if [[ $depth -eq 0 ]]; then
    rel_to_root="../"
  else
    rel_to_root=$(printf '../%.0s' $(seq 0 "$depth"))
  fi
  submodule="${sub_path##*/}"

  echo "$name $root $submodule $rel_to_root $sub_path PATH: $path"
done < filtered-projects-path.txt
