# !/bin/sh
# This script builds and installs OpenSSL with FIPS support on an Alpine Linux system.
OPENSSL_VERSION=3.5.0

apk update
apk upgrade --no-cache
apk add --no-cache perl gcc musl-dev linux-headers make gcompat curl libc6-compat openssl-dev

cd /
wget https://www.openssl.org/source/openssl-${OPENSSL_VERSION}.tar.gz
tar xf openssl-${OPENSSL_VERSION}.tar.gz

cd openssl-${OPENSSL_VERSION}/
./Configure enable-fips
make install
make install_fips
openssl version
openssl fipsinstall -out /usr/local/ssl/fipsmodule.cnf -module /usr/local/lib64/ossl-modules/fips.so
cp ./providers/fipsmodule.cnf /etc/ssl/
# Verify that the fips.so module was installed correctly
diff ./providers/fips.so /usr/local/lib64/ossl-modules/fips.so

# Create the file with the FIPS ONLY configuration block

cat << 'EOF' > /tmp/openssl_fips_insert.txt
.include /etc/ssl/fipsmodule.cnf

[openssl_init]
providers = provider_sect
alg_section = algorithm_sect

[algorithm_sect]
default_properties = fips=yes

# List of providers to load
[provider_sect]
fips = fips_sect
base = base_sect
default = default_sect

[base_sect]
activate = 1
EOF

# Insert the FIPS ONLY configuration block into the openssl.cnf file after the line that contains "# For FIPS"
awk '/^# For FIPS/{print; system("cat /tmp/openssl_fips_insert.txt"); next}1' /etc/ssl/openssl.cnf > /etc/ssl/openssl.cnf.new && mv /etc/ssl/openssl.cnf.new /etc/ssl/openssl.cnf

# Verify that the FIPS provider is available
/util/wrap.pl -fips apps/openssl list -provider-path providers -provider fips -providers

# Remove the OpenSSL source code to save space
cd /
rm -rf /openssl-${OPENSSL_VERSION}*