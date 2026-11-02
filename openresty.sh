. ./common.sh

INSTALL_DIR="/www/server"
LOCK_DIR="$ROOT/lock"
SRC_DIR="$ROOT/src"
SRC_SUFFIX=".tar.gz"
# OpenResty 源码配置
OPENRESTY_DOWN="https://openresty.org/download/openresty-1.27.1.2.tar.gz"
OPENRESTY_DIR="openresty-1.27.1.2"
OPENRESTY_LOCK="$LOCK_DIR/openresty.lock"
# 锁机制定义
COMMON_LOCK="$LOCK_DIR/openresty.common.lock"

# OpenResty 主安装函数
function install_openresty {
    [ -f "$OPENRESTY_LOCK" ] && return
     
    echo "install openresty..."
    cd "$SRC_DIR" || error_exit "Failed to enter dir: $SRC_DIR"
    [ ! -f "$OPENRESTY_DIR$SRC_SUFFIX" ] && wget "$OPENRESTY_DOWN"
    tar -zxvf "$OPENRESTY_DIR$SRC_SUFFIX"
    cd "$OPENRESTY_DIR" || error_exit "Failed to enter dir: $OPENRESTY_DIR"
    make clean > /dev/null 2>&1

    # 关闭 Nginx 调试符号，缩减体积，提高运行效率
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

    # 调用公共配置块规范化环境并启动
    configure_openresty

    echo  
    echo "install openresty complete."
    touch "$OPENRESTY_LOCK"
}

# 提取公共环境规范函数，消除 install_openresty 和 add_module 的重复冗余代码
function configure_openresty {
    echo "configure openresty..."

    # 显式分离创建子目录，规避非交互式 Shell 花括号扩展不解析的地雷
    mkdir -p "$INSTALL_DIR/$OPENRESTY_DIR/nginx/conf/vhost"
    mkdir -p "$INSTALL_DIR/$OPENRESTY_DIR/nginx/conf/rewrite"

    # 使用 rm -f 只删除软链接本身，绝不使用 -r 递归，彻底规避原文件被抹除的灾难
    [ -L "$INSTALL_DIR/nginx" ] || [ -f "$INSTALL_DIR/nginx" ] && rm -f "$INSTALL_DIR/nginx"

    # 建立标准软链接和快捷命令
    ln -sf "$INSTALL_DIR/$OPENRESTY_DIR/nginx" "$INSTALL_DIR/nginx"
    ln -sf "$INSTALL_DIR/$OPENRESTY_DIR/nginx/sbin/nginx" /usr/local/bin/nginx

    # 复制配置文件和伪静态文件模板
    cp -f "$ROOT/nginx.conf/nginx.conf" "$INSTALL_DIR/$OPENRESTY_DIR/nginx/conf/nginx.conf"
    cp -f "$ROOT/nginx.conf/rule.conf" "$INSTALL_DIR/$OPENRESTY_DIR/nginx/conf/rewrite/rule.conf"

    # 复制静态 Systemd 模板，并赋予标准可读权限
    cp -f "$ROOT/nginx.conf/nginxd.service" /etc/systemd/system/nginxd.service
    chmod 644 /etc/systemd/system/nginxd.service

    # 注册并启动 Systemd 服务
    systemctl daemon-reload
    systemctl enable nginxd >/dev/null 2>&1

    if systemctl is-active nginxd >/dev/null 2>&1; then
        echo "Reloading nginxd service to apply changes..."
        systemctl restart nginxd
    else
        systemctl start nginxd
    fi
}

# 动态添加 Nginx 第三方模块函数
function add_module {
    echo "install module..."
    cd "$SRC_DIR" || error_exit "Failed to enter dir: $SRC_DIR"

    # 幂等性优化：只有在模块目录不存在时才克隆，防止二次运行报错
    if [ ! -d "nginx-push-stream-module" ]; then
        git clone https://github.com/wandenberg/nginx-push-stream-module.git
        [ $? != 0 ] && error_exit "git clone nginx-push-stream-module failed"
    fi

    cd "$OPENRESTY_DIR" || error_exit "Failed to enter dir: $OPENRESTY_DIR"
    make clean > /dev/null 2>&1

    # 环境镜像同步：升级模块时同样关闭调试符号，保证二进制文件一致性
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
        --with-stream_ssl_preread_module \
        --add-module=../nginx-push-stream-module
    [ $? != 0 ] && error_exit "openresty configure err"

    make -j "$(nproc)"
    [ $? != 0 ] && error_exit "openresty make err"
    make install
    [ $? != 0 ] && error_exit "openresty install err"

    # 追加模块后同样刷新运行环境并安全重启
    configure_openresty

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
