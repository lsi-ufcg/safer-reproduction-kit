#!/bin/bash

maven_repos=(
  "green-code-initiative/creedengo-python"
  "Dddddduo/BalloonWords"
  "spring-petclinic/spring-petclinic-langchain4j"
  "spring-petclinic/spring-petclinic-ai"
  "Sigma-Skidder-Team/SigmaRebase"
  "datafusion-contrib/datafusion-sqlancer"
  "ollama4j/ollama4j"
  "loks666/get_jobs"
  "microcks/microcks-testcontainers-java"
  "medblocks/openFHIR"
  "rabbitmq/rabbitmq-amqp-java-client"
  "EntrevistadorInteligente/si-orchestrator"
  "centreformicrosimulation/SimPaths"
  "lhccong/sql-dog-backend"
  "vert-x3/vertx-rabbitmq-client"
  "Cloud-Solutions-International/antikythera"
  "Rapter1990/todowithcouchbase"
  "jeddict/jeddict-ai"
  "imi-ms/MoPat"
  "mabartos/keycloak-adaptive-authn"
  "Rapter1990/parkinglot"
  "facebookincubator/CP4M"
  "ajaynegi45/LibraryMan-API"
  "ZJU-ACES-ISE/chatunitest-maven-plugin"
  "syqu22/spring-boot-shop-sample"
)

gradle_repos=(
  "square/retrofit"
  "Netflix/zuul"
  "junit-team/junit5"
  "Discord4J/Discord4J"
  "google/ExoPlayer"
  "spring-projects/spring-boot"
  "libgdx/libgdx"
  "mendhak/gpslogger"
  "elastic/elasticsearch"
  "LINBIT/linstor-server"
  "CatimaLoyalty/Android"
  "federicoiosue/Omni-Notes"
)

mkdir -p workstation/maven
mkdir -p workstation/gradle

cd workstation/maven
# Maven

for repo in "${maven_repos[@]}"; do
  gh repo fork "$repo" --clone
done

# Gradle

cd ../gradle

for repo in "${gradle_repos[@]}"; do
  gh repo fork "$repo"
done
