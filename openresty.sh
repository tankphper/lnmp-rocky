. ./common.sh

INSTALL_DIR="/www/server"
LOCK_DIR="$ROOT/lock"
SRC_DIR="$ROOT/src"
SRC_SUFFIX=".tar.gz"
# openresty source
OPENRESTY_DOWN="https://openresty.org/download/openresty-1.27.1.2.tar.gz"
OPENRESTY_DIR="openresty-1.27.1.2"
OPENRESTY_LOCK="$LOCK_DIR/openresty.lock"
# common dependency fo nginx
COMMON_LOCK="$LOCK_DIR/openresty.common.lock"

# openresty install function
function install_openresty {
    [ -f "$OPENRESTY_LOCK" ] && return
     
    echo "install openresty..."
    cd "$SRC_DIR" || error_exit "Failed to enter dir: $SRC_DIR"
    [ ! -f "$OPENRESTY_DIR$SRC_SUFFIX" ] && wget "$OPENRESTY_DOWN"
    tar -zxvf "$OPENRESTY_DIR$SRC_SUFFIX"
    cd "$OPENRESTY_DIR" || error_exit "Failed to enter dir: $OPENRESTY_DIR"
    make clean > /dev/null 2>&1

    sed -i "s@CFLAGS=\"$CFLAGS -g\"@#CFLAGS=\"$CFLAGS -g\"@" auto/cc/gcc
    ./configure \
        --prefix="$INSTALL_DIR/$OPENRESTY_DIR" --user=www --group=www \
        --with-pcre2 \
        --with-http_stub_status_module \
        --with-http_gzip_static_module \
        --with-http_realip_module \
        --with-http_ssl_module \
        --with-http_image_filter_module \
        --with-stream \
        --with-stream_realip_module \
        --with-stream_ssl_module \
        --with-stream_ssl_preread_module
    [ $? != 0 ] && error_exit "openresty configure err"

    make -j "$(nproc)"
    [ $? != 0 ] && error_exit "openresty make err"
    make install
    [ $? != 0 ] && error_exit "openresty install err"

    mkdir -p "$INSTALL_DIR/$OPENRESTY_DIR/nginx/conf/vhost"
    mkdir -p "$INSTALL_DIR/$OPENRESTY_DIR/nginx/conf/rewrite"

    [ -L "$INSTALL_DIR/nginx" ] && rm -r "$INSTALL_DIR/nginx"
    ln -sf "$INSTALL_DIR/$OPENRESTY_DIR/nginx" "$INSTALL_DIR/nginx"
    ln -sf "$INSTALL_DIR/$OPENRESTY_DIR/nginx/sbin/nginx" /usr/local/bin/nginx
    # 创建 WEB 目录
    [ ! -d /www/web ] && mkdir -p /www/web
    # 复制配置文件和伪静态文件模板
    cp -f "$ROOT/nginx.conf/nginx.conf" "$INSTALL_DIR/$OPENRESTY_DIR/nginx/conf/nginx.conf"
    cp -f "$ROOT/nginx.conf/rule.conf" "$INSTALL_DIR/$OPENRESTY_DIR/nginx/conf/rewrite/rule.conf"

    # 复制静态 Systemd 模板，并赋予标准读取权限
    cp -f "$ROOT/nginx.conf/nginxd.service" /etc/systemd/system/nginxd.service

    # 注册并启动 Systemd 服务
    systemctl daemon-reload
    systemctl enable nginxd
    systemctl start nginxd

    echo  
    echo "install openresty complete."
    touch "$OPENRESTY_LOCK"
}

# add nginx third module
function add_module {
    echo "install module..."
    cd "$SRC_DIR" || error_exit "Failed to enter dir: $SRC_DIR"
    git clone https://github.com/wandenberg/nginx-push-stream-module.git
    cd "$OPENRESTY_DIR" || error_exit "Failed to enter dir: $OPENRESTY_DIR"
    ./configure \
        --prefix="$INSTALL_DIR/$OPENRESTY_DIR" --user=www --group=www \
        --with-pcre2 \
        --with-http_stub_status_module \
        --with-http_gzip_static_module \
        --with-http_realip_module \
        --with-http_ssl_module \
        --with-http_image_filter_module \
        --with-stream \
        --with-stream_realip_module \
        --with-stream_ssl_module \
        --with-stream_ssl_preread_module \
        --add-module=../nginx-push-stream-module
    [ $? != 0 ] && error_exit "openresty configure err"

    make -j "$(nproc)"
    [ $? != 0 ] && error_exit "openresty make err"
    make install
    [ $? != 0 ] && error_exit "openresty install err"

    echo  
    echo "add module complete."
}

# install common dependency
# nginx gzip depend zlib zlib-devel
# nginx ssl depend openssl openssl-devel
# nginx image_filter module depend gd gd-devel
# nginx user:group is www:www
function install_common {
    [ -f "$COMMON_LOCK" ] && return
    # 启用 Rocky 9 的官方代码就绪库（CRB）和安装 EPEL 源
    dnf install -y epel-release >/dev/null 2>&1
    dnf config-manager --set-enabled crb >/dev/null 2>&1
    # 强行刷新 DNF 缓存，确保系统能够立刻识别来自 EPEL 的高级开发包
    dnf makecache >/dev/null 2>&1

    echo "install dependency..."
    dnf install -y sudo wget gcc gcc-c++ make cmake autoconf automake \
        zlib zlib-devel openssl openssl-devel gd gd-devel \
        pcre2-devel perl-FindBin perl-File-Compare
    [ $? != 0 ] && error_exit "common dependence install err"

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
    install_openresty
}

if [[ $1 = "module" ]]; then
    add_module
else
    start_install
fi
