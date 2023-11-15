ARG alpineVersion=3.18
ARG nodeVersion=21
FROM node:$nodeVersion-alpine$alpineVersion

RUN apk update
RUN apk add --no-cache perl gcc musl-dev linux-headers make gcompat curl

RUN wget https://www.openssl.org/source/openssl-3.0.8.tar.gz
RUN tar xf openssl-3.0.8.tar.gz
WORKDIR openssl-3.0.8/
RUN ./Configure enable-fips
RUN make install
RUN make install_fips
RUN openssl version
RUN openssl fipsinstall -out /usr/local/ssl/fipsmodule.cnf -module /usr/local/lib64/ossl-modules/fips.so

ENV FILEBEAT_VERSION=8.10.4
RUN curl https://artifacts.elastic.co/downloads/beats/filebeat/filebeat-${FILEBEAT_VERSION}-linux-x86_64.tar.gz -o /filebeat.tar.gz && \
    tar xzvf filebeat.tar.gz && \
    rm filebeat.tar.gz && \
    mv filebeat-${FILEBEAT_VERSION}-linux-x86_64 filebeat && \
    cd filebeat && \
    cp filebeat /usr/bin 

RUN apk add logrotate libc6-compat dnsmasq bind-tools jq bash