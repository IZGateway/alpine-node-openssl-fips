# alpine-node-openssl-fips
This is a Docker Alpine Image with Alpine 3.22, Node 24, and OpenSSL 3.5.x (currently 3.5.5) which is not yet FIPS certified but eventually will be.

The Dockerfile automatically fetches the latest patch release of OpenSSL 3.5.x from the official OpenSSL GitHub repository at build time.

The intent of this image is to provide a base Alpine / Node image with a FIPS Certified encryption module for 
FISMA moderate systems requiring a certified encryption module.
