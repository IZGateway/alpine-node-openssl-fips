# Dockerfile
ARG alpineVersion=3.22
ARG nodeVersion=24

# Stage 1: Build OpenSSL FIPS
FROM alpine:$alpineVersion AS openssl-build

ARG OPENSSL_VERSION=3.6.1
ENV LD_LIBRARY_PATH=/usr/local/lib:/usr/local/lib64

RUN apk update \
    && apk upgrade --no-cache \
    && apk add --no-cache bash gcompat libc6-compat 

ENV OPENSSL_FIPS=1
ENV LD_LIBRARY_PATH=/usr/local/lib:/usr/local/lib64:/usr/lib/ossl-modules
    
# Update, upgrade, install packages in one layer
RUN apk add --no-cache musl-dev linux-headers make perl openssl-dev wget gcc \
    && wget https://github.com/openssl/openssl/releases/download/openssl-${OPENSSL_VERSION}/openssl-${OPENSSL_VERSION}.tar.gz \
    && tar xf openssl-${OPENSSL_VERSION}.tar.gz \
    && cd openssl-${OPENSSL_VERSION} \
    && ./Configure enable-fips \
    && make -j$(nproc) \ 
    && make install \
    && cp /usr/local/lib64/ossl-modules/fips.so /usr/lib/ossl-modules/ \
    && openssl fipsinstall -out /usr/local/ssl/fipsmodule.cnf -module /usr/lib/ossl-modules/fips.so

# Insert FIPS ONLY configuration block
COPY openssl_fips_insert.txt /tmp/openssl_fips_insert.txt
RUN tr -d '\r' < /tmp/openssl_fips_insert.txt > /tmp/openssl_fips_insert_unix.txt \
    && mv /tmp/openssl_fips_insert_unix.txt /tmp/openssl_fips_insert.txt
    
RUN awk '/^# For FIPS/ { print; system("cat /tmp/openssl_fips_insert.txt"); skip=1; next } \
     /^# fips = fips_sect/ { skip=0; next } \
     skip { next } \
     { print }' /usr/local/ssl/openssl.cnf > /usr/local/ssl/openssl.cnf.fips
RUN mv /usr/local/ssl/openssl.cnf /usr/local/ssl/openssl.cnf.dist
RUN cp /usr/local/ssl/openssl.cnf.fips /usr/local/ssl/openssl.cnf
RUN openssl version -d -a 
RUN openssl list -providers
    
# Stage 2: Main image
FROM alpine:$alpineVersion

ENV OPENSSL_FIPS=1
ENV LD_LIBRARY_PATH=/usr/local/lib:/usr/local/lib64:/usr/lib/ossl-modules

# Update, upgrade, install packages (including alpine dynamically linked node), and update npm in one layer
RUN apk update \
    && apk upgrade --no-cache \
    && apk add --no-cache curl logrotate dnsmasq bind-tools jq bash vim gcompat libc6-compat nodejs npm \ 
    && npm update -g

# Copy OpenSSL from build stage
COPY --from=openssl-build /usr/local /usr/local
COPY --from=openssl-build /usr/lib/ossl-modules/fips.so /usr/lib/ossl-modules/fips.so

# Download and install filebeat and metricbeat in one layer
RUN export ELASTIC_VERSION=$(curl -s https://api.github.com/repos/elastic/beats/releases/latest | jq -r .tag_name | sed 's/^v//') \
    && curl https://artifacts.elastic.co/downloads/beats/filebeat/filebeat-${ELASTIC_VERSION}-linux-x86_64.tar.gz -o /filebeat.tar.gz \
    && tar xzvf /filebeat.tar.gz \
    && rm /filebeat.tar.gz \
    && mv filebeat-${ELASTIC_VERSION}-linux-x86_64 filebeat \
    && cd filebeat \
    && cp filebeat /usr/bin \
    && mkdir -p /usr/share/filebeat/data \
    && chmod 775 /usr/share/filebeat /usr/share/filebeat/data \
    && cd / \
    && curl https://artifacts.elastic.co/downloads/beats/metricbeat/metricbeat-${ELASTIC_VERSION}-linux-x86_64.tar.gz -o /metricbeat.tar.gz \
    && tar xzvf /metricbeat.tar.gz \
    && rm /metricbeat.tar.gz \
    && mv metricbeat-${ELASTIC_VERSION}-linux-x86_64 metricbeat \
    && cd metricbeat \
    && cp metricbeat /usr/bin \
    && mkdir -p /usr/share/metricbeat/data \
    && chmod 775 /usr/share/metricbeat /usr/share/metricbeat/data \
    && openssl list -providers 


