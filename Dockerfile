FROM debian:jessie-slim

ENV PHP_INI_DIR=/usr/local/etc/php
ENV OPENSSL_VERSION=1.0.1t

ENV PHP_BUILD_DEPS \
	autoconf2.13 \
	lemon \
	libbison-dev \
	libcurl4-openssl-dev \
	libfl-dev \
	libmhash-dev \
	libmysqlclient-dev \
	libpcre3-dev \
	libreadline6-dev \
	librecode-dev \
	libsqlite3-dev \
	libssl-dev \
	libxml2-dev

ENV PHP_RUNTIME_DEPS \
	libmhash2 \
	libmysqlclient18 \
	libpcre3 \
	librecode0 \
	libsqlite3-0 \
	libssl1.0.0 \
	libxml2 \
	xz-utils

ENV BUILD_TOOLS \
	autoconf \
	bison \
	bisonc++ \
	ca-certificates \
	curl \
	dpkg-dev \
	file \
	flex \
	g++ \
	gcc \
	libc-dev \
	make \
	patch \
	pkg-config \
	re2c \
	xz-utils

ENV RUNTIME_TOOLS \
	ca-certificates \
	curl

# Fix repository 404
RUN rm /etc/apt/sources.list && echo "deb http://archive.debian.org/debian-security jessie/updates main" >> /etc/apt/sources.list.d/jessie.list && echo "deb http://archive.debian.org/debian jessie main" >> /etc/apt/sources.list.d/jessie.list

###
### Build OpenSSL
###
RUN set -eux \
# Install Dependencies
	&& apt-get update \
	&& apt-get install -y --no-install-recommends --no-install-suggests --force-yes \
		${BUILD_TOOLS} \
# Fetch OpenSSL
    && cd /tmp \
	&& mkdir openssl \
	&& update-ca-certificates \
	&& curl -sS -k -L --fail "https://www.openssl.org/source/openssl-$OPENSSL_VERSION.tar.gz" -o openssl.tar.gz \
	&& curl -sS -k -L --fail "https://www.openssl.org/source/openssl-$OPENSSL_VERSION.tar.gz.asc" -o openssl.tar.gz.asc \
	&& tar -xzf openssl.tar.gz -C openssl --strip-components=1 \
	&& cd /tmp/openssl \
# Build OpenSSL
	&& ./config \
	&& make depend \
	&& make -j"$(nproc)" \
	&& make install \
# Cleanup
	&& rm -rf /tmp/* \
# Ensure libs are linked to correct architecture directory
	&& debMultiarch="$(dpkg-architecture --query DEB_BUILD_MULTIARCH)" \
	&& mkdir -p "/usr/local/ssl/lib/${debMultiarch}" \
	&& ln -s /usr/local/ssl/lib/* "/usr/local/ssl/lib/${debMultiarch}/" \
# Remove Dependencies
	&& apt-get purge -y --auto-remove -o APT::AutoRemove::RecommendsImportant=false -o APT::AutoRemove::SuggestsImportant=false \
		${BUILD_TOOLS} \
	&& apt-get clean \
	&& rm -rf /var/lib/apt/lists/*
###
### Setup PHP directories
###
RUN set -eux \
	&& mkdir -p ${PHP_INI_DIR}/conf.d \
	&& mkdir -p /usr/src/php
###
### Build PHP
###
COPY data/php/php-5.2.17*.patch /tmp/
RUN set -eux \
# Install Dependencies
	&& apt-get update \
	&& apt-get install -y --no-install-recommends --no-install-suggests --force-yes \
		${PHP_BUILD_DEPS} \
		${BUILD_TOOLS} \
# Setup Requirements
	&& curl -sS -k -L --fail "http://museum.php.net/php5/php-5.2.17.tar.gz" -o /usr/src/php.tar.gz \
	&& tar xzvf /usr/src/php.tar.gz -C /usr/src/php/ \
	&& cd /usr/src/php/php-5.2.17  \
# Extract and apply patches
	&& patch -p1 < /tmp/php-5.2.17-libxml2.patch \
	&& patch -p1 < /tmp/php-5.2.17-openssl.patch \
	&& patch -p1 < /tmp/php-5.2.17-fpm.patch \
	&& (patch -p0 < /tmp/php-5.2.17-curl.patch || true) \
    && gnuArch="$(dpkg-architecture --query DEB_BUILD_GNU_TYPE)" \
	&& debMultiarch="$(dpkg-architecture --query DEB_BUILD_MULTIARCH)" \
	\
	# https://bugs.php.net/bug.php?id=74125
	&& if [ ! -d /usr/include/curl ]; then \
		ln -sT "/usr/include/${debMultiarch}/curl" /usr/local/include/curl; \
	fi \
# Build PHP
	&& ./configure \
		--host="${gnuArch}" \
		--with-libdir="/lib/${debMultiarch}/" \
		--with-config-file-path="${PHP_INI_DIR}" \
		--with-config-file-scan-dir="${PHP_INI_DIR}/conf.d" \
# --enable-ftp is included here because ftp_ssl_connect() needs ftp to be compiled statically (see https://github.com/docker-library/php/issues/236)
		--enable-ftp \
		--with-openssl-dir=/usr/local/ssl \
		\
# --enable-mbstring is included here because otherwise there's no way to get pecl to use it properly (see https://github.com/docker-library/php/issues/195)
		--enable-mbstring \
		\
# PHP-FPM support
		--enable-fastcgi \
		--enable-force-cgi-redirect \
		--enable-fpm \
		--with-fpm-conf="/usr/local/etc/php-fpm.conf" \
# https://github.com/docker-library/php/issues/439
		--with-mhash \
		\
		--with-curl \
		--with-openssl=/usr/local/ssl \
		--with-readline \
		--with-recode \
		--with-zlib \
	&& make -j"$(nproc)" \
	&& make install \
# Cleanup
	&& make clean \
	&& { find /usr/local/bin /usr/local/sbin -type f -executable -exec strip --strip-all '{}' + || true; } \
	&& rm -rf /tmp/* /usr/src/php \
# Remove Dependencie
	&& apt-get purge -y --auto-remove -o APT::AutoRemove::RecommendsImportant=false -o APT::AutoRemove::SuggestsImportant=false \
		${PHP_BUILD_DEPS} \
		${BUILD_TOOLS} \
# Install Run-time requirements
	&& apt-get update \
	&& apt-get install -y --no-install-recommends --no-install-suggests --force-yes \
		${PHP_RUNTIME_DEPS} \
		${RUNTIME_TOOLS} \
	&& apt-get clean \
	&& rm -rf /var/lib/apt/lists/* \
# Setup extension dir
	&& mkdir -p "$(php -r 'echo ini_get("extension_dir");')"
COPY data/docker-php-* /usr/local/bin/
COPY data/php-fpm /usr/local/sbin/php-fpm

WORKDIR /var/www/html
COPY data/php-fpm.conf /usr/local/etc/
COPY data/php.ini /usr/local/etc/php/php.ini

EXPOSE 9000
CMD ["php-fpm"]