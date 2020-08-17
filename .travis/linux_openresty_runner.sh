#!/usr/bin/env bash
#
# Licensed to the Apache Software Foundation (ASF) under one or more
# contributor license agreements.  See the NOTICE file distributed with
# this work for additional information regarding copyright ownership.
# The ASF licenses this file to You under the Apache License, Version 2.0
# (the "License"); you may not use this file except in compliance with
# the License.  You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

set -ex

export_or_prefix() {
    export OPENRESTY_PREFIX="/usr/local/openresty-debug"
}

create_lua_deps() {
    echo "Create lua deps cache"

    make deps
    luarocks install luacov-coveralls --tree=deps --local > build.log 2>&1 || (cat build.log && exit 1)

    sudo rm -rf build-cache/deps
    sudo cp -r deps build-cache/
    sudo cp rockspec/apisix-master-0.rockspec build-cache/
}

before_install() {
    sudo cpanm --notest Test::Nginx >build.log 2>&1 || (cat build.log && exit 1)
    docker pull redis:3.0-alpine
    docker run --rm -itd -p 6379:6379 --name apisix_redis redis:3.0-alpine
    docker run --rm -itd -e HTTP_PORT=8888 -e HTTPS_PORT=9999 -p 8888:8888 -p 9999:9999 mendhak/http-https-echo
    # Runs Keycloak version 10.0.2 with inbuilt policies for unit tests
    docker run --rm -itd -e KEYCLOAK_USER=admin -e KEYCLOAK_PASSWORD=123456 -p 8090:8080 -p 8443:8443 sshniro/keycloak-apisix
    # spin up kafka cluster for tests (1 zookeper and 1 kafka instance)
    docker pull bitnami/zookeeper:3.6.0
    docker pull bitnami/kafka:latest
    docker network create kafka-net --driver bridge
    docker run --name zookeeper-server -d -p 2181:2181 --network kafka-net -e ALLOW_ANONYMOUS_LOGIN=yes bitnami/zookeeper:3.6.0
    docker run --name kafka-server1 -d --network kafka-net -e ALLOW_PLAINTEXT_LISTENER=yes -e KAFKA_CFG_ZOOKEEPER_CONNECT=zookeeper-server:2181 -e KAFKA_CFG_ADVERTISED_LISTENERS=PLAINTEXT://127.0.0.1:9092 -p 9092:9092 -e KAFKA_CFG_AUTO_CREATE_TOPICS_ENABLE=true bitnami/kafka:latest
    docker pull bitinit/eureka
    docker run --name eureka -d -p 8761:8761 --env ENVIRONMENT=apisix --env spring.application.name=apisix-eureka --env server.port=8761 --env eureka.instance.ip-address=127.0.0.1 --env eureka.client.registerWithEureka=true --env eureka.client.fetchRegistry=false --env eureka.client.serviceUrl.defaultZone=http://127.0.0.1:8761/eureka/ bitinit/eureka
    sleep 5
    docker exec -i kafka-server1 /opt/bitnami/kafka/bin/kafka-topics.sh --create --zookeeper zookeeper-server:2181 --replication-factor 1 --partitions 1 --topic test2
}

do_install() {
    export_or_prefix
    if [ $(arch) == "aarch64" ]; then
        wget https://dl.google.com/go/go1.13.linux-arm64.tar.gz
        sudo tar -xvf go1.13.linux-arm64.tar.gz
        sudo mv go /usr/local
        export GOROOT=/usr/local/go
        export GOPATH=/github/workspace
        export PATH=$GOPATH/bin:$GOROOT/bin:$PATH
        go version
    fi
    sudo apt-get -y install libpcre3-dev libssl-dev perl make build-essential curl zlib1g zlib1g-dev unzip git lsof
    sudo apt-get -y install libtemplate-perl dh-systemd systemtap-sdt-dev perl gnupg dh-make bzr-builddeb
    wget -qO - https://openresty.org/package/pubkey.gpg | sudo apt-key add -
    sudo apt-get -y update --fix-missing
    sudo apt-get -y install software-properties-common
    sudo add-apt-repository -y "deb http://openresty.org/package/ubuntu $(lsb_release -sc) main"
    sudo add-apt-repository -y ppa:longsleep/golang-backports
    sudo apt-get update
    sudo apt-get -y install lua5.1 liblua5.1-0-dev
    if [ $(arch) == "aarch64" ]; then
        git clone https://github.com/prakritichauhan07/openresty-packaging
        cd openresty-packaging/deb/
        pwd
        sudo make -j4 zlib-build
        ls
        dpkg -i openresty-zlib_1.2.11-3~bionic1_arm64.deb
        dpkg -i openresty-zlib-dev_1.2.11-3~bionic1_arm64.deb
        sudo make -j4 pcre-build
        dpkg -i openresty-pcre_8.44-1~bionic1_arm64.deb
        dpkg -i openresty-pcre-dev_8.44-1~bionic1_arm64.deb
        sudo make openssl111-debug-build
        dpkg -i openresty-openssl111-debug_1.1.1g-2~bionic1_arm64.deb
        dpkg -i openresty-openssl111-debug-dev_1.1.1g-2~bionic1_arm64.deb
        sudo make openresty-debug-build
        dpkg -i openresty-debug_1.17.8.2-1~bionic1_arm64.deb
        cd ../..
        sudo rm -rf openresty-packaging/
    else
        git clone https://github.com/prakritichauhan07/openresty-packaging
        cd openresty-packaging/deb/
        pwd
        sudo make -j4 zlib-build
        ls
        dpkg -i openresty-zlib_1.2.11-3~bionic1_amd64.deb
        dpkg -i openresty-zlib-dev_1.2.11-3~bionic1_amd64.deb
        sudo make -j4 pcre-build
        dpkg -i openresty-pcre_8.44-1~bionic1_amd64.deb
        dpkg -i openresty-pcre-dev_8.44-1~bionic1_amd64.deb
        sudo make openssl111-debug-build
        dpkg -i openresty-openssl111-debug_1.1.1g-2~bionic1_amd64.deb
        dpkg -i openresty-openssl111-debug-dev_1.1.1g-2~bionic1_amd64.deb
        sudo make openresty-debug-build
        dpkg -i openresty-debug_1.17.8.2-1~bionic1_amd64.deb
        cd ../..
        sudo rm -rf openresty-packaging
        fi

    wget https://github.com/luarocks/luarocks/archive/v2.4.4.tar.gz
    tar -xf v2.4.4.tar.gz
    cd luarocks-2.4.4
    ./configure --prefix=/usr > build.log 2>&1 || (cat build.log && exit 1)
    make build > build.log 2>&1 || (cat build.log && exit 1)
    sudo make install > build.log 2>&1 || (cat build.log && exit 1)
    cd ..
    rm -rf luarocks-2.4.4

    sudo luarocks install luacheck > build.log 2>&1 || (cat build.log && exit 1)

    export GO111MOUDULE=on

    if [ ! -f "build-cache/apisix-master-0.rockspec" ]; then
        create_lua_deps

    else
        src=`md5sum rockspec/apisix-master-0.rockspec | awk '{print $1}'`
        src_cp=`md5sum build-cache/apisix-master-0.rockspec | awk '{print $1}'`
        if [ "$src" = "$src_cp" ]; then
            echo "Use lua deps cache"
            sudo cp -r build-cache/deps ./
        else
            create_lua_deps
        fi
    fi

    # sudo apt-get install tree -y
    # tree deps

    git clone https://github.com/iresty/test-nginx.git test-nginx
    make utils

    git clone https://github.com/apache/openwhisk-utilities.git .travis/openwhisk-utilities
    cp .travis/ASF* .travis/openwhisk-utilities/scancode/

    ls -l ./
    if [ ! -f "build-cache/grpc_server_example" ]; then
        git clone https://github.com/iresty/grpc_server_example
        cd grpc_server_example
        go build -o ../build-cache/grpc_server_example main.go
        cd ..
        sudo rm -rf grpc_server_example/
    fi

    if [ ! -f "build-cache/proto/helloworld.proto" ]; then
        if [ ! -f "grpc_server_example/main.go" ]; then
            git clone https://github.com/iresty/grpc_server_example.git grpc_server_example
        fi

        cd grpc_server_example/
        mv proto/ ../build-cache/
        cd ..
    fi

    if [ ! -f "build-cache/grpcurl" ]; then
        git clone https://github.com/fullstorydev/grpcurl
        cd grpcurl/cmd/grpcurl/
        go build -o ../../../build-cache/grpcurl
        cd ../../../
        sudo rm -rf grpcurl/
    fi
}

script() {
    export_or_prefix
    export PATH=$OPENRESTY_PREFIX/nginx/sbin:$OPENRESTY_PREFIX/luajit/bin:$OPENRESTY_PREFIX/bin:$PATH
    export ETCD_UNSUPPORTED_ARCH="arm64"
    openresty -V
    sudo service etcd stop
    mkdir -p ~/etcd-data
    /usr/bin/etcd --listen-client-urls 'http://0.0.0.0:2379' --advertise-client-urls='http://0.0.0.0:2379' --data-dir ~/etcd-data > /dev/null 2>&1 &
    etcd --version
    sleep 5

    ./build-cache/grpc_server_example &

    ./bin/apisix help
    ./bin/apisix init
    ./bin/apisix init_etcd
    ./bin/apisix start

    #start again  --> fial
    res=`./bin/apisix start`
    if [ "$res" != "APISIX is running..." ]; then
        echo "failed: APISIX runs repeatedly"
        exit 1
    fi

    #kill apisix
    sudo kill -9 `ps aux | grep apisix | grep nginx | awk '{print $2}'`

    #start -> ok
    res=`./bin/apisix start`
    if [ "$res" == "APISIX is running..." ]; then
        echo "failed: shouldn't stop APISIX running after kill the old process."
        exit 1
    fi

    sleep 1
    cat logs/error.log

    sudo sh ./t/grpc-proxy-test.sh
    sleep 1

    ./bin/apisix stop
    sleep 1

    make lint && make license-check || exit 1
    APISIX_ENABLE_LUACOV=1 PERL5LIB=.:$PERL5LIB prove -Itest-nginx/lib -r t
}

after_success() {
    cat luacov.stats.out
    luacov-coveralls
}

case_opt=$1
shift

case ${case_opt} in
before_install)
    before_install "$@"
    ;;
do_install)
    do_install "$@"
    ;;
script)
    script "$@"
    ;;
after_success)
    after_success "$@"
    ;;
esac
