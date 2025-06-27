ARG alpineVersion=3.20
ARG nodeVersion=22
FROM node:$nodeVersion-alpine$alpineVersion

ENV OPENSSL_VERSION=3.5.0
# Update Base Image
RUN apk update
RUN apk upgrade --no-cache
RUN apk add --no-cache perl gcc musl-dev linux-headers make gcompat curl libc6-compat

# Update Node Modules
RUN npm outdated -g || true
RUN npm update -g
RUN npm outdated -g
RUN wget https://www.openssl.org/source/openssl-${OPENSSL_VERSION}.tar.gz
RUN tar xf openssl-${OPENSSL_VERSION}.tar.gz

# Set ELASTIC_VERSION to the version supported in the AudaciousSearch Elastic Search
# environment at https://cloud.elastic.co/deployments/96949b9e33264bbba8e8934a7c7984de
ENV ELASTIC_VERSION=9.0.2
RUN curl https://artifacts.elastic.co/downloads/beats/filebeat/filebeat-${ELASTIC_VERSION}-linux-x86_64.tar.gz -o /filebeat.tar.gz 
RUN tar xzvf filebeat.tar.gz && \
    rm filebeat.tar.gz && \
    mv filebeat-${ELASTIC_VERSION}-linux-x86_64 filebeat && \
    cd filebeat && \
    cp filebeat /usr/bin && \
    mkdir -p /usr/share/filebeat/data && \
    chmod 775 /usr/share/filebeat /usr/share/filebeat/data

RUN curl https://artifacts.elastic.co/downloads/beats/metricbeat/metricbeat-${ELASTIC_VERSION}-linux-x86_64.tar.gz -o /metricbeat.tar.gz
RUN tar xzvf /metricbeat.tar.gz && \
    rm metricbeat.tar.gz && \
    mv metricbeat-${ELASTIC_VERSION}-linux-x86_64 metricbeat && \
    cd metricbeat && \
    cp metricbeat /usr/bin && \
    mkdir -p /usr/share/metricbeat/data && \
    chmod 775 /usr/share/metricbeat /usr/share/metricbeat/data
    
WORKDIR openssl-${OPENSSL_VERSION}/
RUN ./Configure enable-fips
RUN make install
RUN make install_fips
RUN openssl version
RUN openssl fipsinstall -out /usr/local/ssl/fipsmodule.cnf -module /usr/local/lib64/ossl-modules/fips.so

RUN apk add logrotate dnsmasq bind-tools jq bash
