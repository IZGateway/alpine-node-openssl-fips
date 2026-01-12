# Dockerfile
ARG alpineVersion=3.22
ARG nodeVersion=24
FROM node:$nodeVersion-alpine$alpineVersion

ENV OPENSSL_VERSION=3.5.4

# Update, upgrade, install packages, and update npm in one layer
RUN apk update && \
    apk upgrade --no-cache && \
    apk add --no-cache curl logrotate dnsmasq bind-tools jq bash vim && \
    npm update -g

# Download and install filebeat and metricbeat in one layer
RUN export ELASTIC_VERSION=$(curl -s https://api.github.com/repos/elastic/beats/releases/latest | jq -r .tag_name | sed 's/^v//') && \
    curl https://artifacts.elastic.co/downloads/beats/filebeat/filebeat-${ELASTIC_VERSION}-linux-x86_64.tar.gz -o /filebeat.tar.gz && \
    tar xzvf /filebeat.tar.gz && \
    rm /filebeat.tar.gz && \
    mv filebeat-${ELASTIC_VERSION}-linux-x86_64 filebeat && \
    cd filebeat && \
    cp filebeat /usr/bin && \
    mkdir -p /usr/share/filebeat/data && \
    chmod 775 /usr/share/filebeat /usr/share/filebeat/data && \
    cd / && \
    curl https://artifacts.elastic.co/downloads/beats/metricbeat/metricbeat-${ELASTIC_VERSION}-linux-x86_64.tar.gz -o /metricbeat.tar.gz && \
    tar xzvf /metricbeat.tar.gz && \
    rm /metricbeat.tar.gz && \
    mv metricbeat-${ELASTIC_VERSION}-linux-x86_64 metricbeat && \
    cd metricbeat && \
    cp metricbeat /usr/bin && \
    mkdir -p /usr/share/metricbeat/data && \
    chmod 775 /usr/share/metricbeat /usr/share/metricbeat/data

WORKDIR /

# Download, build, and install OpenSSL FIPS in one layer
RUN apk add --no-cache gcc musl-dev linux-headers make perl gcompat libc6-compat openssl-dev && \
    wget https://github.com/openssl/openssl/releases/download/openssl-${OPENSSL_VERSION}/openssl-${OPENSSL_VERSION}.tar.gz && \
    tar xf openssl-${OPENSSL_VERSION}.tar.gz && \
    cd openssl-${OPENSSL_VERSION} && \
    ./Configure enable-fips && \
    make install && \
    make install_fips && \
    openssl version -d -a && \
    cp /usr/local/lib64/ossl-modules/fips.so /usr/lib/ossl-modules/ && \
    openssl fipsinstall -out /etc/fipsmodule.cnf -module /usr/lib/ossl-modules/fips.so && \
    cp ./providers/fipsmodule.cnf /etc/ssl/ && \
    diff ./providers/fips.so /usr/lib/ossl-modules/fips.so && \
    cd / && \
    apk del gcc musl-dev linux-headers make perl openssl-dev && \
    rm -rf /var/cache/apk/* /tmp/* /openssl-${OPENSSL_VERSION}*

# Insert FIPS ONLY configuration block
COPY openssl_fips_insert.txt /tmp/openssl_fips_insert.txt
RUN awk '/^# For FIPS/ { print; system("cat /tmp/openssl_fips_insert.txt"); skip=1; next } \
     /^# fips = fips_sect/ { skip=0; next } \
     skip { next } \
     { print }' /etc/ssl/openssl.cnf > /etc/ssl/openssl.cnf.new && \
    mv /etc/ssl/openssl.cnf /etc/ssl/openssl.cnf.bak && \
    mv /etc/ssl/openssl.cnf.new /etc/ssl/openssl.cnf

