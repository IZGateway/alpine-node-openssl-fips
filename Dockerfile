# Dockerfile
ARG alpineVersion=3.22
ARG nodeVersion=24

FROM node:$nodeVersion-alpine$alpineVersion
ENV OPENSSL_VERSION=3.5.4

# Stage 1: Build OpenSSL FIPS
FROM node:24-alpine3.22 AS openssl-build

ARG OPENSSL_VERSION=3.5.4

# Update, upgrade, install packages, and update npm in one layer
RUN apk update \
    && apk upgrade --no-cache \
    && apk add --no-cache curl logrotate dnsmasq bind-tools jq bash vim  musl-dev linux-headers make perl gcompat libc6-compat openssl-dev wget gcc \
    && npm update -g \
    && wget https://github.com/openssl/openssl/releases/download/openssl-${OPENSSL_VERSION}/openssl-${OPENSSL_VERSION}.tar.gz \
    && tar xf openssl-${OPENSSL_VERSION}.tar.gz \
    && cd openssl-${OPENSSL_VERSION} \
    && ./Configure enable-fips \
    && make install \
    && make install_fips \
    && openssl fipsinstall -out /etc/fipsmodule.cnf -module /usr/lib/ossl-modules/fips.so \
    && cp ./providers/fipsmodule.cnf /etc/ssl/ \
    && diff ./providers/fips.so /usr/lib/ossl-modules/fips.so 

# Stage 2: Main image
FROM node:24-alpine3.22

# Update, upgrade, install packages, and update npm in one layer
RUN apk update && \
    apk upgrade --no-cache && \
    apk add --no-cache curl logrotate dnsmasq bind-tools jq bash vim gcompat libc6-compat && \
    npm update -g

# Copy OpenSSL from build stage
COPY --from=openssl-build /usr/local /usr/local
COPY --from=openssl-build /usr/lib/ossl-modules/fips.so /usr/lib/ossl-modules/fips.so
COPY --from=openssl-build /etc/ssl/fipsmodule.cnf /etc/ssl/fipsmodule.cnf
   
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

# Check OpenSSL Version data
RUN openssl version -d -a 

# Insert FIPS ONLY configuration block
COPY openssl_fips_insert.txt /tmp/openssl_fips_insert.txt
RUN awk '/^# For FIPS/ { print; system("cat /tmp/openssl_fips_insert.txt"); skip=1; next } \
     /^# fips = fips_sect/ { skip=0; next } \
     skip { next } \
     { print }' /etc/ssl/openssl.cnf > /etc/ssl/openssl.cnf.new && \
    mv /etc/ssl/openssl.cnf /etc/ssl/openssl.cnf.bak && \
    mv /etc/ssl/openssl.cnf.new /etc/ssl/openssl.cnf

# Check OpenSSL Version data
RUN openssl version -d -a 
