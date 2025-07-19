FROM debian:bookworm as bookworm
ARG PHP_VERSION=8.4.4
ARG ONIGURUMA_VERSION=6.9.10
ARG LIBXML_VERSION=2.13.5
WORKDIR /local/src

# Copy SHIM source to /local/src
COPY phpw.c /local/src/phpw.c

# Apt-Install
RUN apt-get update && \
	apt-get --no-install-recommends -y install \
	build-essential \
	automake \
	autoconf \
	libtool \
	pkg-config \
	flex \
	make \
	re2c \
	git \
	pv \
	ca-certificates \
	python3 \
	wget && \
	apt-get remove --purge -yqq bison

# Install emscripten sdk
RUN \
	git clone  https://github.com/emscripten-core/emsdk.git && \
	cd emsdk && \
	./emsdk install latest && \
	./emsdk activate latest

# Download PHP and Set-Up Configure
RUN \
	git clone https://github.com/php/php-src.git php-src --branch php-$PHP_VERSION --single-branch --depth 1 && \
	cd php-src && \
	./buildconf --force

# Setting ENV vars
ENV PATH=/local/src/emsdk:/local/src/emsdk/upstream/emscripten:/usr/local/bin:/usr/bin
ENV EMSDK=/local/src/emsdk
ENV EMSDK_NODE=/local/src/emsdk/node/20.18.0_64bit/bin/node

# Create install directory
RUN mkdir -p /local/install

# Compile mbstring regex library, and set its env vars
RUN git clone https://github.com/kkos/oniguruma --branch v$ONIGURUMA_VERSION  --single-branch --depth 1 && \
	cd oniguruma && \
	autoreconf -vfi && \
	emconfigure ./configure --prefix=/local/install --disable-shared && \
	emmake make && \
	emmake make install
ENV ONIG_LIBS="-L/local/install"
ENV ONIG_CFLAGS="-I/local/install/include"

# Compile libxml and related extensions, and set its env vars
RUN git clone https://gitlab.gnome.org/GNOME/libxml2.git libxml2 --branch v$LIBXML_VERSION  --single-branch --depth 1 && \
	cd libxml2 && \
	emconfigure ./autogen.sh --prefix=/local/install --enable-static --disable-shared --with-python=no --with-threads=no && \
	emmake make -j`nproc` && \
	emmake make install
ENV LIBXML_LIBS="-L/local/install"
ENV LIBXML_CFLAGS="-I/local/install/include/libxml2"

COPY pcre-8.45.tar.gz /local/src/
RUN tar -xzf pcre-8.45.tar.gz && \
	cd pcre-8.45 && \
	emconfigure ./configure --prefix=/usr/local/pcre-8.45 \
			--disable-jit --disable-shared \
            --enable-utf8 \
            --enable-unicode-properties && \
	make -j$(nproc) && \
	make install

COPY ./bison26.patch /local/src/bison26.patch
RUN wget http://ftp.gnu.org/gnu/bison/bison-2.6.4.tar.gz && \
    tar -xvf bison-2.6.4.tar.gz && \
    rm bison-2.6.4.tar.gz && \
    cd bison-2.6.4 && \
	git apply --no-index /local/src/bison26.patch && \
    ./configure --prefix=/usr/local/bison --with-libiconv-prefix=/usr/local/libiconv/ && \
    make && \
    make install

ENV PATH="${PATH}:/usr/local/bison/bin"

RUN cd php-src && \
	emconfigure ./configure --disable-all --disable-cgi --disable-cli \
	--host=x86_64-linux-gnu --build=x86_64-linux-gnu \
	--with-pcre-regex=/usr/local/pcre-8.45 --with-pcre-dir=/usr/local/pcre-8.45 \
	--enable-embed=static \
	--enable-calendar --enable-ctype

# PHP <= 7.3 is not very good at detecting the presence of the POSIX readdir_r function
# so we need to force it to be enabled.
RUN echo "#define HAVE_POSIX_READDIR_R 1" >> "/local/src/php-src/main/php_config.h"
COPY ./php5-glibc-fix.patch /local/src/php5-glibc-fix.patch
RUN git apply --no-index php5-glibc-fix.patch --ignore-whitespace

# Compile WASM shim
RUN \
	emcc -O2 -I php-src/. -I php-src/Zend -I php-src/main -I php-src/TSRM -c phpw.c -o phpw.o

# Compile PHP
RUN \
	cd php-src && \
	emmake make -j`nproc`

COPY examples examples

# Create PHP-WASM
RUN mkdir -p /build && \
	emcc -o /build/php-web.mjs \
	-O2 --llvm-lto 2 \
	-s EXPORTED_FUNCTIONS='["_phpw", "_phpw_flush", "_phpw_exec", "_phpw_run", "_chdir", "_setenv", "_php_embed_init", "_php_embed_shutdown", "_zend_eval_string"]' \
	-s EXPORTED_RUNTIME_METHODS='["ccall", "UTF8ToString", "lengthBytesUTF8", "FS"]' \
	-s ENVIRONMENT=web \
	-s MAXIMUM_MEMORY=128mb -s INITIAL_MEMORY=128mb -s ALLOW_MEMORY_GROWTH=0 \
	-s ASSERTIONS=0 -s ERROR_ON_UNDEFINED_SYMBOLS=0 -s MODULARIZE=1 -s INVOKE_RUN=0 -s LZ4=1 -s EXPORT_ES6=1 \
	-s EXPORT_NAME=createPhpModule \
	phpw.o php-src/libs/libphp5.a \
	/local/install/lib/libxml2.a \
	/local/install/lib/libonig.a \
	/local/src/pcre-8.45/.libs/libpcre.a \
	php-src/libs/libphp5.a

RUN mkdir -p /build && \
	emcc -o /build/php-cli.mjs \
	-O2 --llvm-lto 2 \
	-s EXPORTED_FUNCTIONS='["_phpw", "_phpw_flush", "_phpw_exec", "_phpw_run", "_chdir", "_setenv", "_php_embed_init", "_php_embed_shutdown", "_zend_eval_string"]' \
	-s EXPORTED_RUNTIME_METHODS='["ccall", "UTF8ToString", "lengthBytesUTF8", "FS"]' \
	-s ENVIRONMENT=node \
	-s MAXIMUM_MEMORY=128mb -s INITIAL_MEMORY=128mb -s ALLOW_MEMORY_GROWTH=0 \
	-s ASSERTIONS=0 -s ERROR_ON_UNDEFINED_SYMBOLS=0 -s MODULARIZE=1 -s INVOKE_RUN=0 -s LZ4=1 -s EXPORT_ES6=1 \
	-s EXPORT_NAME=createPhpModule \
	phpw.o php-src/libs/libphp5.a \
	/local/install/lib/libxml2.a \
	/local/install/lib/libonig.a \
	/local/src/pcre-8.45/.libs/libpcre.a \
	php-src/libs/libphp5.a

# Save file
FROM scratch
COPY --from=bookworm /build/ .
