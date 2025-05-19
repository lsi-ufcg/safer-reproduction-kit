#!/bin/bash

mkdir -p outputs/stdout
mkdir -p outputs/stderr

cd safer
touch .env
echo "SAFER_ROOT_PATH=$(pwd)" > .env

cd ..

# Maven

./bash/run-experiment.sh workstation/maven/creedengo-python 0
./bash/run-experiment.sh workstation/maven/BalloonWords 1
./bash/run-experiment.sh workstation/maven/spring-petclinic-langchain4j 2
./bash/run-experiment.sh workstation/maven/spring-petclinic-ai 3
./bash/run-experiment.sh workstation/maven/SigmaRebase 4
./bash/run-experiment.sh workstation/maven/datafusion-sqlancer 5
./bash/run-experiment.sh workstation/maven/ollama4j 6
./bash/run-experiment.sh workstation/maven/get_jobs 7
./bash/run-experiment.sh workstation/maven/microcks-testcontainers-java 8
./bash/run-experiment.sh workstation/maven/openFHIR 9
./bash/run-experiment.sh workstation/maven/rabbitmq-amqp-java-client 10
./bash/run-experiment.sh workstation/maven/si-orchestrator 11
./bash/run-experiment.sh workstation/maven/SimPaths 12
./bash/run-experiment.sh workstation/maven/sql-dog-backend 13
./bash/run-experiment.sh workstation/maven/vertx-rabbitmq-client 14
./bash/run-experiment.sh workstation/maven/antikythera 15
./bash/run-experiment.sh workstation/maven/todowithcouchbase 16
./bash/run-experiment.sh workstation/maven/jeddict-ai 17
./bash/run-experiment.sh workstation/maven/MoPat 18
./bash/run-experiment.sh workstation/maven/keycloak-adaptive-authn 19
./bash/run-experiment.sh workstation/maven/parkinglot 20
./bash/run-experiment.sh workstation/maven/CP4M 21
./bash/run-experiment.sh workstation/maven/LibraryMan-API 22
./bash/run-experiment.sh workstation/maven/chatunitest-maven-plugin 23
./bash/run-experiment.sh workstation/maven/spring-boot-shop-sample 24

# Gradle

./bash/run-experiment.sh workstation/gradle/retrofit 25
./bash/run-experiment.sh workstation/gradle/zuul 26
./bash/run-experiment.sh workstation/gradle/junit5 27
./bash/run-experiment.sh workstation/gradle/Discord4J 28
./bash/run-experiment.sh workstation/gradle/ExoPlayer 29
./bash/run-experiment.sh workstation/gradle/spring-boot 30
./bash/run-experiment.sh workstation/gradle/libgdx 31
./bash/run-experiment.sh workstation/gradle/gpslogger 32
./bash/run-experiment.sh workstation/gradle/elasticsearch 33
./bash/run-experiment.sh workstation/gradle/linstor-server 34
./bash/run-experiment.sh workstation/gradle/Android 35
./bash/run-experiment.sh workstation/gradle/Omni-Notes 36
