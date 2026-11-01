. ./common.sh

# PHP 7.4 (and PHP 8.0) are not compatible with OpenSSL 3. 
# Either use PHP 8.1, or stick with OpenSSL 1.1 with these older PHP versions.
read -p "Enter php version like 8.3.36: " INPUT_VERSION
PHP_VERSION="${INPUT_VERSION:-8.3.36}"

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
    
    #[ ! -f "/usr/lib64/libiconv.so" ] && install_libiconv
    #[ ! -f "/usr/local/mcrypt/lib/libmcrypt.so" ] && install_mcrypt
    #[ ! -f "/usr/local/include/oniguruma.h" ] && install_oniguruma
    #[ ! -f "/usr/local/include/zip.h" ] && install_libzip

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
        --with-config-file-scan-dir="$INSTALL_DIR/$PHP_DIR/etc/php.d" \
        --enable-fpm --with-fpm-user=www --with-fpm-group=www \
        --enable-mysqlnd --with-mysqli=mysqlnd --with-pdo-mysql=mysqlnd \
        --with-openssl --with-zlib --with-curl \
        --enable-mbstring --enable-opcache --enable-soap --enable-bcmath --enable-calendar \
        --with-jpeg \
        --with-webp \
        --with-freetype \
        --with-zstd \
        --with-zip \
        --with-pic \
        --enable-gd \
        --enable-intl \
        --enable-sockets \
        --enable-pcntl \
        --enable-shmop \
        --enable-exif \
        --enable-inline-optimization \
        --enable-mbregex \
        --enable-ftp \
        --enable-xml \
        --with-libxml \
        --with-gettext \
        --with-iconv \
        --disable-rpath --disable-ipv6 --disable-debug
    [ $? != 0 ] && error_exit "php configure err"

    make ZEND_EXTRA_LIBS='-liconv' -j "$(nproc)"
    [ $? != 0 ] && error_exit "php make err"
    make install
    [ $? != 0 ] && error_exit "php install err"

    # 建立多版本公共软链接
    ln -sf "$INSTALL_DIR/$PHP_DIR" "$INSTALL_DIR/php"

    # 将全局快捷命令安全注入自定义用户 bin 目录下
    ln -sf "$INSTALL_DIR/php/bin/php" /usr/local/bin/php
    ln -sf "$INSTALL_DIR/php/bin/phpize" /usr/local/bin/phpize
    ln -sf "$INSTALL_DIR/php/bin/php-config" /usr/local/bin/php-config
    ln -sf "$INSTALL_DIR/php/sbin/php-fpm" /usr/local/sbin/php-fpm

    # 如果 /usr/bin/php 不存在，则建立安全的保底软链
    if [ ! -f /usr/bin/php ] && [ ! -L /usr/bin/php ]; then
        ln -sf "$INSTALL_DIR/php/bin/php" /usr/bin/php
    fi

    # 初始化并隔离每个独立版本的配置文件
    [ ! -d "$INSTALL_DIR/$PHP_DIR/etc" ] && mkdir -p "$INSTALL_DIR/$PHP_DIR/etc"
    [ ! -d "$INSTALL_DIR/$PHP_DIR/etc/php.d" ] && mkdir -p "$INSTALL_DIR/$PHP_DIR/etc/php.d"

    # 复制并初始化 php.ini 基础配置
    cp -f php.ini-production "$INSTALL_DIR/$PHP_DIR/etc/php.ini"
    sed -i 's@^;date.timezone.*@date.timezone = Asia/Shanghai@' "$INSTALL_DIR/$PHP_DIR/etc/php.ini"

    # 复制并初始化 php-fpm 基础配置
    cp -f "$INSTALL_DIR/$PHP_DIR/etc/php-fpm.conf.default" "$INSTALL_DIR/$PHP_DIR/etc/php-fpm.conf"
    cp -f "$INSTALL_DIR/$PHP_DIR/etc/php-fpm.d/www.conf.default" "$INSTALL_DIR/$PHP_DIR/etc/php-fpm.d/www.conf"
    sed -i "s#^;pid = run/php-fpm.pid#pid = run/php-fpm.pid#" "$INSTALL_DIR/$PHP_DIR/etc/php-fpm.conf"

    # 复制静态 Systemd 模板，并赋予标准读取权限
    cp -f ./sapi/fpm/php-fpm.service /etc/systemd/system/
    chmod 644 /etc/systemd/system/php-fpm.service
    sed -i "s#@prefix@#$INSTALL_DIR/php#" /etc/systemd/system/php-fpm.service
    sed -i "s#@exec_prefix@#$INSTALL_DIR/php#" /etc/systemd/system/php-fpm.service

    # 注册并启动 Systemd 服务
    systemctl daemon-reload
    systemctl enable php-fpm
    systemctl start php-fpm

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

    ./configure --prefix=/usr/local/libiconv --enable-static
    [ $? != 0 ] && error_exit "libiconv configure err"

    # 彻底抹除旧源码中在现代 glibc 环境下会导致编译崩溃的 gets 包装宏隐患
    if [ -f "srclib/stdio.in.h" ]; then
        sed -i -e '/_GL_WARN_ON_USE (gets,.*)/d' srclib/stdio.in.h
    fi

    make -j "$(nproc)"
    [ $? != 0 ] && error_exit "libiconv make err"
    make install
    [ $? != 0 ] && error_exit "libiconv install err"

    # link to /usr/lib64
    ln -sf /usr/local/libiconv/lib/libiconv.so /usr/lib64/
    ln -sf /usr/local/libiconv/lib/libiconv.so.2 /usr/lib64/

    # 将实际的 lib 目录写进系统动态链接缓存中，完美防止 PHP 运行时找不到库
    echo '/usr/local/libiconv/lib' > /etc/ld.so.conf.d/libiconv-wdl.conf
    # 刷新动态链接库
    ldconfig

    cd "$SRC_DIR" || error_exit "Failed to enter dir: $SRC_DIR"
    rm -fr "$ICONV_SRC"
    
    echo 
    echo "install libiconv complete."
    touch "$ICONV_LOCK"
}

# mcrypt install function
# mcrypt_dir=/usr/local/mcrypt
function install_mcrypt {
    [ -f "$MCRYPT_LOCK" ] && return
    echo "install mcrypt..."

    cd "$SRC_DIR" || error_exit "Failed to enter dir: $SRC_DIR"
    [ ! -f "$MCRYPT_SRC$SRC_SUFFIX" ] && wget "$MCRYPT_DOWN"
    tar -zxvf "$MCRYPT_SRC$SRC_SUFFIX"
    cd "$MCRYPT_SRC" || error_exit "Failed to enter dir: $MCRYPT_SRC"
    ./configure --prefix=/usr/local/mcrypt
    [ $? != 0 ] && error_exit "mcrypt configure err"

    make
    [ $? != 0 ] && error_exit "mcrypt make err"
    make install
    [ $? != 0 ] && error_exit "mcrypt install err"

    # 将标准库路径注入系统动态缓存并刷新
    echo '/usr/local/mcrypt/lib' > /etc/ld.so.conf.d/mcrypt-wdl.conf
    # 刷新动态链接库
    ldconfig

    # 精准拆解 libltdl 的编译流，规避 && 串联时可能引发的间接错误漏检隐患
    cd libltdl || error_exit "Failed to enter dir: libltdl"
    ./configure --enable-ltdl-install
    [ $? != 0 ] && error_exit "mcrypt ltdl configure err"
    make -j "$(nproc)"
    [ $? != 0 ] && error_exit "mcrypt ltdl make err"
    make install
    [ $? != 0 ] && error_exit "mcrypt ltdl install err"

    cd "$SRC_DIR"|| error_exit "Failed to enter dir: $SRC_DIR"
    rm -fr "$MCRYPT_SRC"
    
    echo 
    echo "install mcrypt complete."
    touch "$MCRYPT_LOCK"
}

# mbstring depend oniguruma
# oniguruma install function
# oniguruma_dir=/usr/local
function install_oniguruma {
    [ -f "$ONIGURUMA_LOCK" ] && return
    echo "install oniguruma..."

    cd "$SRC_DIR" || error_exit "Failed to enter dir: $SRC_DIR"

    # 统一使用你的变量名
    [ ! -f "$ONIGURUMA_SRC.tar.gz" ] && wget "$ONIGURUMA_DOWN" -O "$ONIGURUMA_SRC.tar.gz"
    tar -zxvf "$ONIGURUMA_SRC.tar.gz"
    cd "$ONIGURUMA_SRC" || error_exit "Failed to enter dir: $ONIGURUMA_SRC"

    # 安全拆解 ./autogen.sh，防止命令连击时无法精准定位错误
    if [ -f "autogen.sh" ]; then
        ./autogen.sh
        [ $? != 0 ] && error_exit "oniguruma autogen err"
    fi

    # 标准的 /usr/local 前缀锁定，防止去污染 Rocky Linux 9 官方保护的核心系统
    ./configure --prefix=/usr/local --enable-shared --enable-static
    [ $? != 0 ] && error_exit "oniguruma configure err"

    make
    [ $? != 0 ] && error_exit "oniguruma make err"
    make install
    [ $? != 0 ] && error_exit "oniguruma install err"
   
    # 将实际的 64 位和 32 位动态库路径及 pkgconfig 注册进系统
    # 彻底杜绝后续 PHP 8.3 编译 --enable-mbstring 时报 "oniguruma not found" 的硬伤
    echo '/usr/local/lib' > /etc/ld.so.conf.d/oniguruma-wdl.conf
    # 刷新动态链接库
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
    # 规范下载：统一使用你的变量名，并加上防护
    [ ! -f "$LIBZIP_SRC.tar.gz" ] && wget "$LIBZIP_DOWN" -O "$LIBZIP_SRC.tar.gz"
    tar -zxvf "$LIBZIP_SRC.tar.gz"
    cd "$LIBZIP_SRC" || error_exit "Failed to enter dir: $LIBZIP_SRC"

    mkdir -p build
    cd build || error_exit "Failed to enter dir: build"

    cmake ..
    [ $? != 0 ] && error_exit "libzip configure err"

    # 执行编译，开启多核加速榨干 2h4g 性能
    make -j "$(nproc)"
    [ $? != 0 ] && error_exit "libzip make err"
    make install
    [ $? != 0 ] && error_exit "libzip install err"

    # 将编译产出的 64 位 pkgconfig 路径注入全局系统变量中，使用单引号
    # 彻底杜绝后续 PHP 8.3 编译时报 "libzip >= 0.11 not found" 的经典死锁
    if [ ! -f /etc/profile.d/pkgconfig.sh ]; then
        echo 'export PKG_CONFIG_PATH=/usr/local/lib64/pkgconfig:/usr/local/lib/pkgconfig:/usr/lib64/pkgconfig:/usr/lib/pkgconfig:$PKG_CONFIG_PATH' > /etc/profile.d/pkgconfig.sh
        chmod +x /etc/profile.d/pkgconfig.sh
    fi
    # 让当前 shell 脚本进程立刻在内存中加载这个变量
    export PKG_CONFIG_PATH="/usr/local/lib64/pkgconfig:/usr/local/lib/pkgconfig:/usr/lib64/pkgconfig:/usr/lib/pkgconfig:$PKG_CONFIG_PATH"

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
    dnf install -y wget gcc gcc-c++ make autoconf gd-devel freetype-devel libxml2-devel \
        libjpeg-turbo-devel libpng-devel openssl-devel sqlite-devel libtool \
        libcurl-devel patch ncurses-devel bzip2 libcap-devel diffutils \
        bison libicu-devel net-tools psmisc vim vim-enhanced \
        zip unzip telnet tcpdump ipset lsof iptables iptables-services \
        libzip libzip-devel oniguruma-devel libwebp-devel libzstd-devel libmcrypt-devel
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
