#!/bin/bash

mkdir -p outputs/stdout
mkdir -p outputs/stderr

cd safer
touch .env
echo "SAFER_ROOT_PATH=$(pwd)" > .env

cd ..

# Maven

./bash/run-experiment.sh workstation/maven/antikythera 1
./bash/run-experiment.sh workstation/maven/BalloonWords 2
./bash/run-experiment.sh workstation/maven/chatunitest-maven-plugin 3
./bash/run-experiment.sh workstation/maven/CP4M 4
./bash/run-experiment.sh workstation/maven/creedengo-python 5
./bash/run-experiment.sh workstation/maven/datafusion-sqlancer 6
./bash/run-experiment.sh workstation/maven/get_jobs 7
./bash/run-experiment.sh workstation/maven/jeddict-ai 8
./bash/run-experiment.sh workstation/maven/keycloak-adaptive-authn 9
./bash/run-experiment.sh workstation/maven/LibraryMan-API 10
./bash/run-experiment.sh workstation/maven/microcks-testcontainers-java 11
./bash/run-experiment.sh workstation/maven/MoPat 12
./bash/run-experiment.sh workstation/maven/openFHIR 13
./bash/run-experiment.sh workstation/maven/ollama4j 14
./bash/run-experiment.sh workstation/maven/parkinglot 15
./bash/run-experiment.sh workstation/maven/rabbitmq-amqp-java-client 16
./bash/run-experiment.sh workstation/maven/si-orchestrator 17
./bash/run-experiment.sh workstation/maven/SigmaRebase 18
./bash/run-experiment.sh workstation/maven/SimPaths 19
./bash/run-experiment.sh workstation/maven/spring-boot-shop-sample 20
./bash/run-experiment.sh workstation/maven/spring-petclinic-ai 21
./bash/run-experiment.sh workstation/maven/spring-petclinic-langchain4j 22
./bash/run-experiment.sh workstation/maven/sql-dog-backend 23
./bash/run-experiment.sh workstation/maven/todowithcouchbase 24
./bash/run-experiment.sh workstation/maven/vertx-rabbitmq-client 25

# Gradle

./bash/run-experiment.sh workstation/gradle/Android 26
./bash/run-experiment.sh workstation/gradle/Discord4J 27
./bash/run-experiment.sh workstation/gradle/elasticsearch 28
./bash/run-experiment.sh workstation/gradle/ExoPlayer 29
./bash/run-experiment.sh workstation/gradle/gpslogger 30
./bash/run-experiment.sh workstation/gradle/junit5 31
./bash/run-experiment.sh workstation/gradle/libgdx 32
./bash/run-experiment.sh workstation/gradle/linstor-server 33
./bash/run-experiment.sh workstation/gradle/Omni-Notes 34
./bash/run-experiment.sh workstation/gradle/retrofit 35
./bash/run-experiment.sh workstation/gradle/spring-boot 36
./bash/run-experiment.sh workstation/gradle/zuul 37
