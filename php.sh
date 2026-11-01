. ./common.sh

# PHP 7.4 (and PHP 8.0) are not compatible with OpenSSL 3. 
# Either use PHP 8.1, or stick with OpenSSL 1.1 with these older PHP versions.
read -p "Enter php version like 8.3.36: " PHP_VERSION

INSTALL_DIR="/www/server"
SRC_DIR="$ROOT/src"
LOCK_DIR="$ROOT/lock"
SRC_SUFFIX=".tar.gz"
# php source
PHP_DOWN="http://hk1.php.net/distributions/php-$PHP_VERSION.tar.gz"
PHP_SRC="php-$PHP_VERSION"
PHP_DIR="$PHP_SRC"
PHP_LOCK="$LOCK_DIR/php.lock"
# dependency of php
ICONV_DOWN="http://ftp.gnu.org/gnu/libiconv/libiconv-1.16.tar.gz"
ICONV_SRC="libiconv-1.16"
ICONV_LOCK="$LOCK_DIR/php.iconv.lock"
# php-7.2.x or newer need compile https://pecl.php.net/get/mcrypt-1.0.1.tgz by handle and add mcrypt.so to php.ini
MCRYPT_DOWN="https://gitlab.com/lnmp-shell/lnmp-files/-/raw/master/libmcrypt-2.5.8.tar.gz"
MCRYPT_SRC="libmcrypt-2.5.8"
MCRYPT_LOCK="$LOCK_DIR/php.mcrypt.lock"
# mbstring depend oniguruma
ONIGURUMA_DOWN="https://github.com/kkos/oniguruma/archive/v6.9.4.tar.gz"
ONIGURUMA_SRC="oniguruma-6.9.4"
ONIGURUMA_LOCK="$LOCK_DIR/php.oniguruma.lock"
# php-7.4.x depend libzip >= 0.11 libzip != 1.3.1 libzip != 1.7.0 
LIBZIP_DOWN="https://libzip.org/download/libzip-1.10.1.tar.gz"
LIBZIP_SRC="libzip-1.10.1"
LIBZIP_LOCK="$LOCK_DIR/php.libzip.lock"
# common dependency for php
COMMON_LOCK="$LOCK_DIR/php.common.lock"

# php-8.x install function
# nginx: --enable-fpm --with-fpm-user=www --with-fpm-group=www
function install_php {
    
    #[ ! -f /usr/lib64/libiconv.so ] && install_libiconv
    #[ ! -f /usr/lib64/libmcrypt.so ] && install_mcrypt
    #[ ! -f /usr/include/oniguruma.h ] && install_oniguruma
    #if version_gt "$PHP_VERSION" "7.4.0"; then (install_libzip) fi

    [ -f "$PHP_LOCK" ] && return

    echo "install php..."

    cd "$SRC_DIR" || error_exit "Failed to enter dir: $SRC_DIR"
    [ ! -f "$PHP_SRC$SRC_SUFFIX" ] && wget --no-check-certificate "$PHP_DOWN"
    tar -zxvf "$PHP_SRC$SRC_SUFFIX"
    cd "$PHP_SRC" || error_exit "Failed to enter dir: $PHP_SRC"
    make clean > /dev/null 2>&1
    ./configure \
        --prefix="$INSTALL_DIR/$PHP_DIR" \
        --with-config-file-path="$INSTALL_DIR/$PHP_DIR/etc" \
        --enable-fpm --with-fpm-user=www --with-fpm-group=www \
        --enable-mysqlnd --with-mysql=mysqlnd --with-mysqli=mysqlnd --with-pdo-mysql=mysqlnd \
        --with-iconv --with-mcrypt=/usr \
        --enable-gd --with-freetype --with-jpeg --with-zip \
        --with-zlib --with-libxml-dir=/usr --with-curl --with-openssl --with-xmlrpc --with-gettext \
        --enable-inline-optimization \
        --enable-mbregex --enable-mbstring --enable-ftp --enable-intl --enable-xml --enable-bcmath \
        --enable-exif --enable-shmop --enable-pcntl --enable-soap --enable-sockets --enable-opcache \
        --disable-rpath --disable-ipv6 --disable-debug
    [ $? != 0 ] && error_exit "php configure err"
    make ZEND_EXTRA_LIBS='-liconv' -j $CPUS
    [ $? != 0 ] && error_exit "php make err"
    make install
    [ $? != 0 ] && error_exit "php install err"
    # php link dir
    ln -sf "$INSTALL_DIR/$PHP_DIR" "$INSTALL_DIR/php"
    # copy php.ini-production to $PHP_DIR
    cp php.ini-production "$INSTALL_DIR/$PHP_DIR/etc/php.ini"
    # replace php.ini config
    sed -i 's@^;date.timezone.*@date.timezone = Asia/Shanghai@' "$INSTALL_DIR/$PHP_DIR/etc/php.ini"
    ln -sf "$INSTALL_DIR/$PHP_DIR/bin/php" /usr/local/bin/php
    ln -sf "$INSTALL_DIR/$PHP_DIR/bin/phpize" /usr/local/bin/phpize
    ln -sf "$INSTALL_DIR/$PHP_DIR/bin/php-config" /usr/local/bin/php-config
    # php version
    cp -f "$INSTALL_DIR/$PHP_DIR/etc/php-fpm.conf.default" "$INSTALL_DIR/$PHP_DIR/etc/php-fpm.conf"
    cp -f "$INSTALL_DIR/$PHP_DIR/etc/php-fpm.d/www.conf.default" "$INSTALL_DIR/$PHP_DIR/etc/php-fpm.d/www.conf"
    # php-fpm config
    sed -i "s@^;pid = run/php-fpm.pid@pid = run/php-fpm.pid@" "$INSTALL_DIR/$PHP_DIR/etc/php-fpm.conf"
    # for php-fpm
    cp -f ./sapi/fpm/php-fpm.service /usr/lib/systemd/system/
    sed -i "s@${prefix}@/www/server/php@" /usr/lib/systemd/system/php-fpm.service
    sed -i "s@${exec_prefix}@/www/server/php@" /usr/lib/systemd/system/php-fpm.service
    # 开机启动
    systemctl daemon-reload
    systemctl start php-fpm.service
    systemctl enable php-fpm.service

    echo  
    echo "install php complete."
    touch "$PHP_LOCK"
}

# libiconv install function
# iconv_dir=/usr/local/libiconv
function install_libiconv {
    [ -f "$ICONV_LOCK" ] && return
    echo "install libiconv..."

    cd "$SRC_DIR" || error_exit "Failed to enter dir: $SRC_DIR"
    [ ! -f "$ICONV_SRC$SRC_SUFFIX" ] && wget "$ICONV_DOWN"
    tar -zxvf "$ICONV_SRC$SRC_SUFFIX"
    cd "$ICONV_SRC" || error_exit "Failed to enter dir: $ICONV_SRC"
    ./configure --prefix=/usr/local/libiconv
    [ $? != 0 ] && error_exit "libiconv configure err"
    make -j "$(nproc)"
    [ $? != 0 ] && error_exit "libiconv make err"
    make install
    [ $? != 0 ] && error_exit "libiconv install err"
    # link to /usr/lib64
    ln -sf /usr/local/libiconv/lib/libiconv.so /usr/lib64/
    ln -sf /usr/local/libiconv/lib/libiconv.so.2 /usr/lib64/
    
    # refresh active lib
    ldconfig
    cd "$SRC_DIR" || error_exit "Failed to enter dir: $SRC_DIR"
    rm -fr "$ICONV_SRC"
    
    echo 
    echo "install libiconv complete."
    touch "$ICONV_LOCK"
}

# mcrypt install function
# mcrypt_dir=/usr
function install_mcrypt {
    [ -f "$MCRYPT_LOCK" ] && return
    echo "install mcrypt..."

    cd "$SRC_DIR" || error_exit "Failed to enter dir: $SRC_DIR"
    [ ! -f "$MCRYPT_SRC$SRC_SUFFIX" ] && wget "$MCRYPT_DOWN"
    tar -zxvf "$MCRYPT_SRC$SRC_SUFFIX"
    cd "$MCRYPT_SRC" || error_exit "Failed to enter dir: $MCRYPT_SRC"
    ./configure --prefix=/usr
    [ $? != 0 ] && error_exit "mcrypt configure err"
    make
    [ $? != 0 ] && error_exit "mcrypt make err"
    make install
    [ $? != 0 ] && error_exit "mcrypt install err"
    
    # refresh active lib
    ldconfig
    cd libltdl || error_exit "Failed to enter dir: libltdl"
    ./configure --enable-ltdl-install && make && make install
    [ $? != 0 ] && error_exit "mcrypt ltdl install err"
    cd "$SRC_DIR"|| error_exit "Failed to enter dir: $SRC_DIR"
    rm -fr "$MCRYPT_SRC"
    
    echo 
    echo "install mcrypt complete."
    touch "$MCRYPT_LOCK"
}

# mbstring depend oniguruma
# Centos 8 install oniguruma
function install_oniguruma {
    [ -f "$ONIGURUMA_LOCK" ] && return
    echo "install oniguruma..."

    cd "$SRC_DIR" || error_exit "Failed to enter dir: $SRC_DIR"
    wget "$ONIGURUMA_DOWN" -O "$ONIGURUMA_SRC.tar.gz"
    tar -zxvf "$ONIGURUMA_SRC.tar.gz"
    cd "$ONIGURUMA_SRC" || error_exit "Failed to enter dir: $ONIGURUMA_SRC"
    ./autogen.sh && ./configure --prefix=/usr
    [ $? != 0 ] && error_exit "oniguruma configure err"
    make
    [ $? != 0 ] && error_exit "oniguruma make err"
    make install
    [ $? != 0 ] && error_exit "oniguruma install err"
   
    # refresh active lib
    ldconfig 
    cd "$SRC_DIR" || error_exit "Failed to enter dir: $SRC_DIR"
    rm -fr "$ONIGURUMA_SRC"

    echo
    echo "install oniguruma complete."
    touch "$ONIGURUMA_LOCK"
}

# php-7.4.x require libzip >= 0.11 libzip != 1.3.1 libzip != 1.7.0
function install_libzip {
    [ -f "$LIBZIP_LOCK" ] && return
    echo "install libzip..."

    cd "$SRC_DIR" || error_exit "Failed to enter dir: $SRC_DIR"
    wget "$LIBZIP_DOWN" -O "$LIBZIP_SRC.tar.gz"
    tar -zxvf "$LIBZIP_SRC.tar.gz"
    cd "$LIBZIP_SRC" || error_exit "Failed to enter dir: $LIBZIP_SRC"
    mkdir build
    cd build || error_exit "Failed to enter dir: build"
    cmake ..
    [ $? != 0 ] && error_exit "libzip make err"
    make install
    [ $? != 0 ] && error_exit "libzip install err"

    #export PKG_CONFIG_PATH="/usr/local/lib/pkgconfig/"
    cd "$SRC_DIR" || error_exit "Failed to enter dir: $SRC_DIR"
    rm -fr "$LIBZIP_SRC"

    echo
    echo "install libzip complete."
    touch "$LIBZIP_LOCK"
}

# install common dependency
# ifconfig command depend net-tools
# php user:group is www:www
function install_common {
    [ -f "$COMMON_LOCK" ] && return
    # 启用 Rocky 9 的官方代码就绪库（CRB）和安装 EPEL 源
    # 很多如 oniguruma-devel 的高阶开发包都在这里面
    dnf config-manager --set-enabled crb >/dev/null 2>&1
    dnf install -y epel-release >/dev/null 2>&1
    # 强行刷新 DNF 缓存，确保系统能够立刻识别来自 EPEL 的高级开发包
    dnf makecache >/dev/null 2>&1
    # Rocky 9 完美适配版依赖包列表
    dnf install -y wget gcc gcc-c++ make autoconf gd-devel \
        freetype-devel libxml2-devel libjpeg-turbo-devel libpng-devel openssl-devel \
        sqlite-devel libtool libzip libzip-devel \
        libcurl-devel patch ncurses-devel bzip2 libcap-devel diffutils \
        bison libicu-devel net-tools psmisc vim vim-enhanced \
        zip unzip telnet tcpdump ipset lsof iptables iptables-services \
        oniguruma-devel libwebp-devel libzstd-devel
    [ $? != 0 ] && error_exit "common dependency install err"

    # 创建专门运行 openresty 和 php-fpm 的系统用户和组
    # 检查 www 用户是否存在，不存在则精准创建
    if ! getent passwd www >/dev/null 2>&1; then
        useradd -U -d /dev/null -s /sbin/nologin -M www > /dev/null 2>&1
    fi
    # -d to set user home_dir=/www
    # -s to set user login shell=/sbin/nologin, you also to set /bin/bash

    # 强制让 chrony 立即同步网络时间
    chronyc -a makestep
    # 将系统时区改为上海
    timedatectl set-timezone Asia/Shanghai
    # 将准确的系统时间写入硬件时钟
    hwclock -w
    
    echo 
    echo "install common dependency complete."
    touch "$COMMON_LOCK"
}

# start install
function start_install {
    [ ! -d "$LOCK_DIR" ] && mkdir -p "$LOCK_DIR"
    install_common
    install_php
}

start_install
