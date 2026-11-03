. ./common.sh

read -p "Enter php version(default: 8.3.36): " INPUT_VERSION
PHP_VERSION="${INPUT_VERSION:-8.3.36}"

INSTALL_DIR="/www/server"
SRC_DIR="$ROOT/src"
LOCK_DIR="$ROOT/lock"
SRC_SUFFIX=".tar.gz"
# php source
PHP_DOWN="http://hk1.php.net/distributions/php-$PHP_VERSION.tar.gz"
PHP_DIR="php-$PHP_VERSION"
PHP_LOCK="$LOCK_DIR/php.lock"
# common dependency for php
COMMON_LOCK="$LOCK_DIR/php.common.lock"

# php-8.x install function
# nginx: --enable-fpm --with-fpm-user=www --with-fpm-group=www
function install_php {
    [ -f "$PHP_LOCK" ] && return

    echo "install php..."

    cd "$SRC_DIR" || error_exit "Failed to enter dir: $SRC_DIR"
    [ ! -f "$PHP_DIR$SRC_SUFFIX" ] && wget --no-check-certificate "$PHP_DOWN"
    tar -zxvf "$PHP_DIR$SRC_SUFFIX"
    cd "$PHP_DIR" || error_exit "Failed to enter dir: $PHP_DIR"

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

    make -j "$(nproc)"
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

    # 在 php-fpm 启动前，创建公共日志目录并赋权给 www 用户
    mkdir -p /www/logs/php
    chown -R www:www /www/logs/php
    chmod 750 /www/logs/php

    # 初始化并隔离每个独立版本的配置文件
    [ ! -d "$INSTALL_DIR/$PHP_DIR/etc" ] && mkdir -p "$INSTALL_DIR/$PHP_DIR/etc"
    [ ! -d "$INSTALL_DIR/$PHP_DIR/etc/php.d" ] && mkdir -p "$INSTALL_DIR/$PHP_DIR/etc/php.d"

    # 复制并初始化 php.ini 基础配置
    cp -f php.ini-production "$INSTALL_DIR/$PHP_DIR/etc/php.ini"
    sed -i 's@^;date.timezone =.*@date.timezone = Asia/Shanghai@' "$INSTALL_DIR/$PHP_DIR/etc/php.ini"
    sed -i "s@^display_errors =.*@display_errors = Off@" "$INSTALL_DIR/$PHP_DIR/etc/php.ini"
    sed -i "s@^log_errors =.*@log_errors = On@" "$INSTALL_DIR/$PHP_DIR/etc/php.ini"
    sed -i "s@^;error_log = php_errors.log.*@error_log = /www/logs/php/php.error.log@" "$INSTALL_DIR/$PHP_DIR/etc/php.ini"

    # 复制并初始化 php-fpm 基础配置
    cp -f "$INSTALL_DIR/$PHP_DIR/etc/php-fpm.conf.default" "$INSTALL_DIR/$PHP_DIR/etc/php-fpm.conf"
    sed -i "s@^;pid = run/php-fpm.pid@pid = run/php-fpm.pid@" "$INSTALL_DIR/$PHP_DIR/etc/php-fpm.conf"
    sed -i "s@^;error_log =.*@error_log = /www/logs/php/php-fpm.error.log@" "$INSTALL_DIR/$PHP_DIR/etc/php-fpm.conf"

    # 复制并初始化 www.conf 基础配置
    cp -f "$INSTALL_DIR/$PHP_DIR/etc/php-fpm.d/www.conf.default" "$INSTALL_DIR/$PHP_DIR/etc/php-fpm.d/www.conf"
    sed -i "s@^listen =.*@listen = /dev/shm/php-cgi.sock@" "$INSTALL_DIR/$PHP_DIR/etc/php-fpm.d/www.conf"
    sed -i "s@^;listen.owner =.*@listen.owner = www@" "$INSTALL_DIR/$PHP_DIR/etc/php-fpm.d/www.conf"
    sed -i "s@^;listen.group =.*@listen.group = www@" "$INSTALL_DIR/$PHP_DIR/etc/php-fpm.d/www.conf"
    sed -i "s@^;listen.mode =.*@listen.mode = 0660@" "$INSTALL_DIR/$PHP_DIR/etc/php-fpm.d/www.conf"
    sed -i "s@^;slowlog =.*@slowlog = /www/logs/php/php-fpm.slow.log@" "$INSTALL_DIR/$PHP_DIR/etc/php-fpm.d/www.conf"
    sed -i "s@^;request_slowlog_timeout =.*@request_slowlog_timeout = 5s@" "$INSTALL_DIR/$PHP_DIR/etc/php-fpm.d/www.conf"
    sed -i "s@^;catch_workers_output =.*@catch_workers_output = yes@" "$INSTALL_DIR/$PHP_DIR/etc/php-fpm.d/www.conf"

    # 复制静态 Systemd 模板，并赋予标准读取权限
    cp -f ./sapi/fpm/php-fpm.service /etc/systemd/system/
    chmod 644 /etc/systemd/system/php-fpm.service
    sed -i "s@$INSTALL_DIR/$PHP_DIR@$INSTALL_DIR/php@" /etc/systemd/system/php-fpm.service

    # 注册并启动 Systemd 服务
    systemctl daemon-reload
    systemctl enable php-fpm
    systemctl start php-fpm

    echo  
    echo "install php complete."
    touch "$PHP_LOCK"
}

# install common dependency
# ifconfig command depend net-tools
# php user:group is www:www
function install_common {
    [ -f "$COMMON_LOCK" ] && return

    echo "install crb and epel..."
    # 启用 Rocky 9 的官方代码就绪库（CRB）和安装 EPEL 源
    # 很多如 oniguruma-devel 的高阶开发包都在这里面
    dnf config-manager --set-enabled crb >/dev/null 2>&1
    dnf install -y epel-release >/dev/null 2>&1
    # 强行刷新 DNF 缓存，确保系统能够立刻识别来自 EPEL 的高级开发包
    dnf makecache >/dev/null 2>&1

    # Rocky 9 完美适配版依赖包列表
    echo "install dependency..."
    dnf install -y wget gcc gcc-c++ make autoconf gd-devel freetype-devel libxml2-devel \
        libjpeg-turbo-devel libpng-devel openssl-devel sqlite-devel libtool \
        libcurl-devel patch ncurses-devel bzip2 libcap-devel diffutils \
        bison libicu-devel net-tools psmisc vim vim-enhanced \
        zip unzip telnet tcpdump ipset lsof iptables iptables-services \
        libzip libzip-devel oniguruma-devel libwebp-devel libzstd-devel libmcrypt-devel
    [ $? != 0 ] && error_exit "common dependency install err"

    # 创建专门运行 openresty 和 php-fpm 的系统用户和组
    # 检查 www 用户是否存在，不存在则精准创建
    # -d to set user home_dir=/www
    # -s to set user login shell=/sbin/nologin, you also to set /bin/bash
    if ! getent passwd www >/dev/null 2>&1; then
        useradd -U -d /dev/null -s /sbin/nologin -M www > /dev/null 2>&1
    fi

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
