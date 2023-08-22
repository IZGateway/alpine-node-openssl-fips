ARG alpineVersion=3.18
ARG nodeVersion=18
FROM node:$nodeVersion-alpine$alpineVersion

RUN apk update
RUN apk add --no-cache perl gcc musl-dev linux-headers make
RUN wget https://www.openssl.org/source/openssl-3.0.8.tar.gz
RUN tar xf openssl-3.0.8.tar.gz
WORKDIR openssl-3.0.8/
RUN ./Configure enable-fips
RUN make install
RUN openssl version
RUN openssl fipsinstall
