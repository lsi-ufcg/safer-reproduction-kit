#!/bin/bash

mkdir -p outputs/stdout
mkdir -p outputs/stderr

cd safer
touch .env
echo "SAFER_ROOT_PATH=$(pwd)" >.env
cd ..

maven_repos=(
  "https://github.com/dromara/lamp-cloud"
  "https://github.com/apache/dubbo-spring-boot-project"
  "https://github.com/apache/dubbo-admin"
  "https://github.com/yzcheng90/X-SpringBoot"
  "https://github.com/hellokaton/30-seconds-of-java8"
  "https://github.com/bz51/SpringBoot-Dubbo-Docker-Jenkins"
  "https://github.com/uber-common/jvm-profiler"
  "https://github.com/LeonardoZ/java-concurrency-patterns"
  "https://github.com/JMCuixy/swagger2word"
  "https://github.com/secure-software-engineering/FlowDroid"
  "https://github.com/kekingcn/spring-boot-klock-starter"
  "https://github.com/liuweijw/fw-cloud-framework"
  "https://github.com/RohitAwate/Everest"
  "https://github.com/NationalSecurityAgency/datawave"
  "https://github.com/aerogear/keycloak-metrics-spi"
  "https://github.com/cnescatlab/sonar-cnes-report"
  "https://github.com/jeecgboot/autopoi"
  "https://github.com/uber/marmaray"
  "https://github.com/parrt/bookish"
  "https://github.com/nnngu/nguSeckill"
  "https://github.com/kiooeht/ModTheSpire"
  "https://github.com/code4everything/efo"
  "https://github.com/lrwinx/shop"
  "https://github.com/niezhiliang/netty-websocket-spring-boot"
  "https://github.com/lingfengsan/MillionHero"
  "https://github.com/hank-whu/turbo-rpc"
  "https://github.com/jakartaee/rest"
  "https://github.com/DropSnorz/OwlPlug"
  "https://github.com/convertigo/convertigo"
  "https://github.com/r2dbc/r2dbc-client"
  "https://github.com/hellokaton/elves"
  "https://github.com/yz-java/common-project"
  "https://github.com/yangwenjie88/delay-queue"
  "https://github.com/amihaiemil/docker-java-api"
  "https://github.com/wsk1103/mini-life"
  "https://github.com/WAng91An/ManagementSystem"
  "https://github.com/hellokaton/java-library-examples"
  "https://github.com/pkanyue/jboot-admin"
  "https://github.com/simplesteph/ec2-masterclass-sampleapp"
  "https://github.com/houbb/junitperf"
  "https://github.com/titinko/utsu"
  "https://github.com/dee1024/sloth"
  "https://github.com/huststl/tmall_ssm"
  "https://github.com/microsoft/botbuilder-java"
  "https://github.com/withstars/Genesis"
  "https://github.com/jchambers/fast-uuid"
  "https://github.com/houbb/markdown-toc"
  "https://github.com/framiere/a-kafka-story"
  "https://github.com/longfeizheng/security-oauth2"
  "https://github.com/SkytAsul/BeautyQuests"
  "https://github.com/goldmansachs/jdmn"
  "https://github.com/yahoo/sherlock"
  "https://github.com/Systems-Modeling/SysML-v2-Pilot-Implementation"
  "https://github.com/jloisel/securing-rest-api-spring-security"
  "https://github.com/sunshanpeng/dark_magic"
  "https://github.com/Jasonandy/java-patterns"
  "https://github.com/hazelcast/hazelcast-jet-demos"
  "https://github.com/runabol/spring-security-passwordless"
  "https://github.com/Nova41/SnowLeopard"
  "https://github.com/MrMicky-FR/FastInv"
  "https://github.com/irsl/jackson-rce-via-spel"
  "https://github.com/eclipse-ee4j/tyrus"
  "https://github.com/bigzidane/springboot-rest-h2-swagger"
  "https://github.com/Leo-Drew-Real/conference_room"
  "https://github.com/dapeng-soa/dapeng-soa"
  "https://github.com/ryandw11/CustomStructures"
  "https://github.com/coderliguoqing/vans"
  "https://github.com/SwordfallYeung/POIExcel"
  "https://github.com/logicaldoc/community"
  "https://github.com/oschina/J2Cache"
  "https://github.com/WinterChenS/springboot-mybatis-demo"
  "https://github.com/twinformatics/eureka-consul-adapter"
  "https://github.com/lucko/jar-relocator"
  "https://github.com/TechPrimers/spring-boot-graphql-query-example"
  "https://github.com/checkstyle/eclipse-cs"
  "https://github.com/IBM/spring-cloud-kubernetes-with-istio"
  "https://github.com/blueapron/kafka-connect-protobuf-converter"
  "https://github.com/siegluo/distributed-lock"
  "https://github.com/societe-generale/rabbitmq-advanced-spring-boot-starter"
  "https://github.com/nbfujx/Goku.Framework.CoreUI"
  "https://github.com/manouti/completablefuture-examples"
  "https://github.com/xmlet/XsdParser"
  "https://github.com/sparrowzoo/sparrow-shell"
  "https://github.com/flamegrapher/flamegrapher"
  "https://github.com/Hualiner/Api-Auto-Test"
  "https://github.com/Vatavuk/excel-io"
  "https://github.com/Nepxion/Permission"
  "https://github.com/ChinaWim/Hospital"
  "https://github.com/shengqi158/Jackson-databind-RCE-PoC"
  "https://github.com/only2dhir/spring-boot-security-oauth2"
  "https://github.com/techpavan/mvn-repo-cleaner"
  "https://github.com/diaozxin007/framework"
  "https://github.com/dee1024/jump-jump-game"
  "https://github.com/StevenWash/xxshop"
  "https://github.com/alertisme/sample"
  "https://github.com/xie-summer/new-cloud"
  "https://github.com/Adobe-Marketing-Cloud/aem-guides-wknd"
  "https://github.com/hawkingfoo/demo-agent"
  "https://github.com/aliyun/elasticsearch-repository-oss"
  "https://github.com/afurculita/VehicleRoutingProblem"
)

# Maven
id=1
for repo in "${maven_repos[@]}"; do
  cd workstation/maven
  git clone --depth 1 $repo.git
  cd ../../
  ./bash/run-experiment.sh workstation/maven/$(basename $repo) $id
    rm -rf workstation/maven/$(basename $repo)
  id=$(($id + 1))
done

# Gradle
# id=1
# for project_path in workstation/gradle/*; do
#   ./bash/run-experiment.sh $project_path $id
#   id=$(($id + 1))
# done
