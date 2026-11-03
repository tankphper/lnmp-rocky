. ./common.sh

SRC_DIR="$ROOT/src"
PHP_VERSION=$(php-config --version)
PHP_PREFIX=$(php-config --prefix)
PHP_API_VER=$(phpize --version | awk '/PHP Api Version/ {print $NF}')
PHP_EXT_DIR=$(php-config --extension-dir)

echo "=================================================="
echo "PHP_VERSION: $PHP_VERSION"
echo "PHP_API_VER: $PHP_API_VER"
echo "PHP_EXT_DIR: $PHP_EXT_DIR"
echo "=================================================="

# add extension file to php.ini
# 完美对齐多版本 php.d 动态扫描规范，且全量双引号加固
function echo_ini {
    # $1 传入扩展名，如 "redis"
    # 直接在专属的 php.d 目录下创建一个独立的 [扩展名.ini] 文件
    echo "extension=$1.so" > "$PHP_PREFIX/etc/php.d/$1.ini"
}

# --enable-async-redis require hiredis library supported
# --enable-http2 require nghttp2 library supported
# swoole-5.1.2 or newer for PHP 8.3
function add_swoole {
    local SWOOLE_VER=${2:-"5.1.2"}
    cd "$SRC_DIR" || error_exit "Failed to enter dir: $SRC_DIR"

    [ ! -f "swoole.tar.gz" ] && wget --no-check-certificate "https://pecl.php.net/get/swoole-$SWOOLE_VER.tgz" -O "swoole.tar.gz"
    # 清理并建立干净的编译临时区
    [ -d "swoole_build" ] && rm -rf "swoole_build"
    mkdir "swoole_build"
    tar -zxvf "swoole.tar.gz" -C "swoole_build" --strip-components=1
    cd "swoole_build" || error_exit "Failed to enter dir: swoole_build"

    phpize
    ./configure \
        --with-php-config="$PHP_PREFIX/bin/php-config" \
        --enable-openssl \
        --enable-async-redis \
        --enable-http2 \
        --enable-mysqlnd \
        --enable-coroutine \
        --enable-sockets
    [ $? != 0 ] && error_exit "swoole configure err"

    make
    [ $? != 0 ] && error_exit "swoole make err"
    make install
    [ $? != 0 ] && error_exit "swoole make install err"

    echo_ini swoole

    # 清理临时编译温床
    cd "$SRC_DIR" && rm -rf "swoole_build"
    echo "swoole-$PROTOBUF_VER installation complete."
}

# protobuf-4.25.0 or newer for PHP 8.3
function add_protobuf {
    local PROTOBUF_VER=${2:-"4.25.0"}
    cd "$SRC_DIR" || error_exit "Failed to enter dir: $SRC_DIR"

    [ ! -f "protobuf.tar.gz" ] && wget --no-check-certificate "https://pecl.php.net/get/protobuf-$PROTOBUF_VER.tgz" -O "protobuf.tar.gz"
    # 清理并建立干净的编译临时区
    [ -d "protobuf_build" ] && rm -rf "protobuf_build"
    mkdir "protobuf_build"
    tar -zxvf "protobuf.tar.gz" -C "protobuf_build" --strip-components=1
    cd "protobuf_build" || error_exit "Failed to enter dir: protobuf_build"

    phpize
    ./configure --with-php-config="$PHP_PREFIX/bin/php-config"
    [ $? != 0 ] && error_exit "protobuf configure err"

    make
    [ $? != 0 ] && error_exit "protobuf make err"
    make install
    [ $? != 0 ] && error_exit "protobuf make install err"

    echo_ini protobuf

    # 清理临时编译温床
    cd "$SRC_DIR" && rm -rf "protobuf_build"
    echo "protobuf-$PROTOBUF_VER installation complete."
}

# php-7.2.x removed mcrypt
# php --ri mcrypt will see version 2.5.8
function add_mcrypt {
    local MCRYPT_VER=${2:-"1.0.4"}
    cd "$SRC_DIR" || error_exit "Failed to enter dir: $SRC_DIR"

    [ ! -f "phpmcrypt.tar.gz" ] && wget --no-check-certificate "https://pecl.php.net/get/mcrypt-$MCRYPT_VER.tgz" -O "phpmcrypt.tar.gz"
    # 清理并建立干净的编译临时区
    [ -d "phpmcrypt_build" ] && rm -rf "phpmcrypt_build"
    mkdir "phpmcrypt_build"
    tar -zxvf "phpmcrypt.tar.gz" -C "phpmcrypt_build" --strip-components=1
    cd "phpmcrypt_build" || error_exit "Failed to enter dir: phpmcrypt_build"

    phpize
    ./configure --with-php-config="$PHP_PREFIX/bin/php-config"
    [ $? != 0 ] && error_exit "phpmcrypt configure err"

    make
    [ $? != 0 ] && error_exit "phpmcrypt make err"
    make install
    [ $? != 0 ] && error_exit "phpmcrypt make install err"

    echo_ini mcrypt

    # 清理临时编译温床
    cd "$SRC_DIR" && rm -rf "phpmcrypt_build"
    echo "phpmcrypt-$MCRYPT_VER installation complete."
}

# phpredis-6.x or newer for PHP 8.3
function add_redis {
    local PHPREDIS_VER=${2:-"6.3.0"}
    cd "$SRC_DIR" || error_exit "Failed to enter dir: $SRC_DIR"

    [ ! -f "phpredis.tar.gz" ] && wget --no-check-certificate "https://pecl.php.net/get/redis-${PHPREDIS_VER}.tgz" -O "phpredis.tar.gz"
    # 清理并建立干净的编译临时区
    [ -d "phpredis_build" ] && rm -rf "phpredis_build"
    mkdir "phpredis_build"
    tar -zxvf "phpredis.tar.gz" -C "phpredis_build" --strip-components=1
    cd "phpredis_build" || error_exit "Failed to enter dir: phpredis_build"

    phpize
    ./configure --with-php-config="$PHP_PREFIX/bin/php-config"
    [ $? != 0 ] && error_exit "phpredis configure err"

    make -j "$(nproc)"
    [ $? != 0 ] && error_exit "phpredis make err"
    make install
    [ $? != 0 ] && error_exit "phpredis make install err"

    echo_ini redis

    # 清理临时编译温床
    cd "$SRC_DIR" && rm -rf "phpredis_build"
    echo "phpredis-$PHPREDIS_VER installation complete."
}

# xlswriter-1.5.5 or newer for PHP 8.3
function add_xlswriter {
    local XLSWRITER_VER=${2:-"3.0.0"}
    cd "$SRC_DIR" || error_exit "Failed to enter dir: $SRC_DIR"

    [ ! -f "xlswriter.tar.gz" ] && wget --no-check-certificate "https://pecl.php.net/get/xlswriter-$XLSWRITER_VER.tgz" -O "xlswriter.tar.gz"
    # 清理并建立干净的编译临时区
    [ -d "xlswriter_build" ] && rm -rf "xlswriter_build"
    mkdir "xlswriter_build"
    tar -zxvf "xlswriter.tar.gz" -C "xlswriter_build" --strip-components=1
    cd "xlswriter_build" || error_exit "Failed to enter dir: xlswriter_build"

    phpize
    ./configure --with-php-config="$PHP_PREFIX/bin/php-config" --enable-reader
    [ $? != 0 ] && error_exit "xlswriter configure err"

    make -j "$(nproc)"
    [ $? != 0 ] && error_exit "xlswriter make err"
    make install
    [ $? != 0 ] && error_exit "xlswriter make install err"

    echo_ini xlswriter

    # 清理临时编译温床
    cd "$SRC_DIR" && rm -rf "xlswriter_build"
    echo "xlswriter-$XLSWRITER_VER installation complete."
}

# 动态分发调用块
if [ -n "$1" ]; then
   # 确保执行安全的参数透传
   type "add_$1" &>/dev/null && add_$1 "$@" || error_exit "Unsupported extension type: add_$1"
fi
