#!/bin/bash
#
# Copyright 2020 G-Research
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

# Script to prepare release, see RELEASE.md for details

set -euo pipefail

# check for clean git status (except for CHANGELOG.md and release.sh)
readarray -t git_status < <(git status -s --untracked-files=no 2>/dev/null | grep -v -e " CHANGELOG.md$" -e " release.sh$")
if [ ${#git_status[@]} -gt 0 ]
then
  echo "There are pending git changes:"
  for (( i=0; i<${#git_status[@]}; i++ )); do echo "${git_status[$i]}" ; done
  exit 1
fi

# check for unreleased entry in CHANGELOG.md
readarray -t changes < <(grep -A 100 "^## \[UNRELEASED\] - YYYY-MM-DD" CHANGELOG.md | grep -B 100 --max-count=1 -E "^## \[[0-9.]+\]" | grep "^-")
if [ ${#changes[@]} -eq 0 ]
then
  echo "Did not find any changes in CHANGELOG.md under '## [UNRELEASED] - YYYY-MM-DD'"
  exit 1
fi

# check this is a SNAPSHOT versions
if ! grep -q "<version>.*-SNAPSHOT</version>" pom.xml
then
  echo "Version in pom is not a SNAPSHOT version, cannot test all versions"
  exit 1
fi

# check for existing cached SNAPSHOT jars
version=$(grep --max-count=1 "<version>.*</version>" pom.xml | sed -E -e "s/\s*<[^>]+>//g" -e "s/-SNAPSHOT//" -e "s/-[0-9.]+//g")
jars=$(find $HOME/.m2 $HOME/.ivy2 -name "*spark-dgraph-connector_*-$version-*-SNAPSHOT.jar")
if [[ -n "$jars" ]]
then
  echo "There are installed SNAPSHOT jars, these may interfere with release tests. These must be deleted first:"
  echo "$jars" | tr '\n' ' '
  echo
  exit 1
fi

# start dgraph test instance
cp dgraph-instance.*.sh /tmp/
if [ -d "/tmp/dgraph-instance" ]
then
  docker=$(/tmp/dgraph-instance.background.sh || (docker container ls >&2 && false) )
else
  docker=$(/tmp/dgraph-instance.background.sh || (docker container ls >&2 && false) )
  sleep 10
  /tmp/dgraph-instance.drop-all.sh
  /tmp/dgraph-instance.schema.sh
  /tmp/dgraph-instance.insert.sh
fi

# testing all versions
./set-version.sh 3.0.3 2.12.10; mvn clean deploy -Dsign; ./test-release.sh
./set-version.sh 3.1.3 2.12.10; mvn clean deploy -Dsign; ./test-release.sh
./set-version.sh 3.2.4 2.12.15; mvn clean deploy -Dsign; ./test-release.sh
./set-version.sh 3.3.2 2.12.15; mvn clean deploy -Dsign; ./test-release.sh
./set-version.sh 3.4.0 2.12.17; mvn clean deploy -Dsign; ./test-release.sh

# stop dgraph test instance
docker stop "$docker"

# all SNAPSHOT versions build, test and complete the example, releasing

# revert pom.xml and examples/scala/pom.xml changes
git checkout pom.xml examples/scala/pom.xml

# get latest and release version
latest=$(grep --max-count=1 "<version>.*</version>" README.md | sed -E -e "s/\s*<[^>]+>//g" -e "s/-[0-9.]+//g")
version=$(grep --max-count=1 "<version>.*</version>" pom.xml | sed -E -e "s/\s*<[^>]+>//g" -e "s/-SNAPSHOT//" -e "s/-[0-9.]+//g")

echo "Releasing ${#changes[@]} changes as version $version:"
for (( i=0; i<${#changes[@]}; i++ )); do echo "${changes[$i]}" ; done

sed -i "s/## \[UNRELEASED\] - YYYY-MM-DD/## [$version] - $(date +%Y-%m-%d)/" CHANGELOG.md
sed -i -e "s/$latest-/$version-/g" -e "s/$latest\./$version./g" README.md
./set-version.sh $version

# commit changes to local repo
echo
echo "Committing release to local git"
git add pom.xml examples/scala/pom.xml CHANGELOG.md README.md
git commit -m "Releasing $version"
git tag -a "v${version}" -m "Release v${version}"

echo "Please inspect git changes:"
git show HEAD
echo "Press <ENTER> to push to origin"
read

echo "Pushing release commit and tag to origin"
git push origin main "v${version}"
echo

# create release
echo "Creating release packages"
./set-version.sh 3.0.3 2.12.10; mvn clean deploy -Dsign; mvn nexus-staging:release
./set-version.sh 3.1.3 2.12.10; mvn clean deploy -Dsign; mvn nexus-staging:release
./set-version.sh 3.2.4 2.12.15; mvn clean deploy -Dsign; mvn nexus-staging:release
./set-version.sh 3.3.2 2.12.15; mvn clean deploy -Dsign; mvn nexus-staging:release
./set-version.sh 3.4.0 2.12.17; mvn clean deploy -Dsign; mvn nexus-staging:release

echo

git checkout pom.xml examples/scala/pom.xml
./bump-version.sh
