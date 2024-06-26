ARG alpineVersion=3.20
ARG nodeVersion=21
FROM node:$nodeVersion-alpine$alpineVersion

RUN apk update
RUN apk add --no-cache perl gcc musl-dev linux-headers make gcompat curl libc6-compat

RUN wget https://www.openssl.org/source/openssl-3.0.8.tar.gz
RUN tar xf openssl-3.0.8.tar.gz

ENV FILEBEAT_VERSION=8.10.4
RUN curl https://artifacts.elastic.co/downloads/beats/filebeat/filebeat-${FILEBEAT_VERSION}-linux-x86_64.tar.gz -o /filebeat.tar.gz 
RUN tar xzvf filebeat.tar.gz && \
    rm filebeat.tar.gz && \
    mv filebeat-${FILEBEAT_VERSION}-linux-x86_64 filebeat && \
    cd filebeat && \
    cp filebeat /usr/bin 

ENV METRICBEAT_VERSION=8.11.3
RUN curl https://artifacts.elastic.co/downloads/beats/metricbeat/metricbeat-${METRICBEAT_VERSION}-linux-x86_64.tar.gz -o /metricbeat.tar.gz
RUN tar xzvf /metricbeat.tar.gz && \
    rm metricbeat.tar.gz && \
    mv metricbeat-${METRICBEAT_VERSION}-linux-x86_64 metricbeat && \
    cd metricbeat && \
    cp metricbeat /usr/bin
    
WORKDIR openssl-3.0.8/
RUN ./Configure enable-fips
RUN make install
RUN make install_fips
RUN openssl version
RUN openssl fipsinstall -out /usr/local/ssl/fipsmodule.cnf -module /usr/local/lib64/ossl-modules/fips.so


RUN apk add logrotate dnsmasq bind-tools jq bash
