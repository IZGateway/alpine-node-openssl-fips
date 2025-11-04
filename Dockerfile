ARG alpineVersion=3.22
ARG nodeVersion=24
FROM node:$nodeVersion-alpine$alpineVersion

ENV OPENSSL_VERSION=3.5.4
# Update Base Image
RUN apk update
RUN apk upgrade --no-cache

# Update npm itself
RUN npm i -g npm@latest && npm cache clean --force

# Verify tar version is updated
RUN npm list -g tar || true

# Update Node Modules
RUN npm outdated -g || true
RUN npm update -g
RUN npm outdated -g

# We need curl to download the Elastic Beats, and for Diagnostics within the container
RUN apk add --no-cache curl
RUN apk add logrotate dnsmasq bind-tools jq bash 

# Set ELASTIC_VERSION to the latest version and pull filebeat 
RUN export ELASTIC_VERSION=$(curl -s https://api.github.com/repos/elastic/beats/releases/latest | jq -r .tag_name | sed 's/^v//') && \
    curl https://artifacts.elastic.co/downloads/beats/filebeat/filebeat-${ELASTIC_VERSION}-linux-x86_64.tar.gz -o /filebeat.tar.gz && \
    tar xzvf filebeat.tar.gz && \
    rm filebeat.tar.gz && \
    mv filebeat-${ELASTIC_VERSION}-linux-x86_64 filebeat && \
    cd filebeat && \
    cp filebeat /usr/bin && \
    mkdir -p /usr/share/filebeat/data && \
    chmod 775 /usr/share/filebeat /usr/share/filebeat/data

# Set ELASTIC_VERSION to the latest version and pull metricbeat 
RUN export ELASTIC_VERSION=$(curl -s https://api.github.com/repos/elastic/beats/releases/latest | jq -r .tag_name | sed 's/^v//') && \
    curl https://artifacts.elastic.co/downloads/beats/metricbeat/metricbeat-${ELASTIC_VERSION}-linux-x86_64.tar.gz -o /metricbeat.tar.gz && \
    tar xzvf /metricbeat.tar.gz && \
    rm metricbeat.tar.gz && \
    mv metricbeat-${ELASTIC_VERSION}-linux-x86_64 metricbeat && \
    cd metricbeat && \
    cp metricbeat /usr/bin && \
    mkdir -p /usr/share/metricbeat/data && \
    chmod 775 /usr/share/metricbeat /usr/share/metricbeat/data
    
WORKDIR /

# Install necessary build dependencies
RUN apk add --no-cache vim perl gcc musl-dev linux-headers make gcompat curl libc6-compat openssl-dev

RUN wget https://github.com/openssl/openssl/releases/download/openssl-${OPENSSL_VERSION}/openssl-${OPENSSL_VERSION}.tar.gz
RUN tar xf openssl-${OPENSSL_VERSION}.tar.gz

WORKDIR /openssl-${OPENSSL_VERSION}
RUN ./Configure enable-fips
RUN make install
RUN make install_fips
RUN openssl version -d -a
RUN cp /usr/local/lib64/ossl-modules/fips.so /usr/lib/ossl-modules/

# Install the FIPS module using the fipsinstall command
RUN openssl fipsinstall -out /etc/fipsmodule.cnf -module /usr/lib/ossl-modules/fips.so
RUN cp ./providers/fipsmodule.cnf /etc/ssl/
# Verify that the fips.so module was installed correctly
RUN diff ./providers/fips.so /usr/lib/ossl-modules/fips.so

# Create the file with the FIPS ONLY configuration block
COPY openssl_fips_insert.txt /tmp/openssl_fips_insert.txt
# Insert the FIPS ONLY configuration block into the openssl.cnf file between line "# For FIPS" and "# fips = fips_sect"
RUN awk '/^# For FIPS/ { print; system("cat /tmp/openssl_fips_insert.txt"); skip=1; next } \
     /^# fips = fips_sect/ { skip=0; next } \
     skip { next } \
     { print }' /etc/ssl/openssl.cnf > /etc/ssl/openssl.cnf.new

RUN mv /etc/ssl/openssl.cnf /etc/ssl/openssl.cnf.bak
RUN mv /etc/ssl/openssl.cnf.new /etc/ssl/openssl.cnf

# Remove the OpenSSL source code to save space
WORKDIR /
RUN rm -rf /openssl-${OPENSSL_VERSION}*

# Running apk del causes problems right now
# RUN apk del vim perl gcc musl-dev linux-headers make gcompat libc6-compat openssl-dev
