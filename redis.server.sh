. ./common.sh

read -p "Enter redis version(default: 7.2.17): " REDIS_VERSION

INSTALL_DIR="/www/server"
SRC_DIR="$ROOT/src"
LOCK_DIR="$ROOT/lock"
SRC_SUFFIX=".tar.gz"
# redis server source
REDIS_DOWN="http://download.redis.io/releases/redis-$REDIS_VERSION.tar.gz"
REDIS_DIR="redis-$REDIS_VERSION"
REDIS_LOCK="$LOCK_DIR/redis.server.lock"
# common dependency for redis
COMMON_LOCK="$LOCK_DIR/redis.common.lock"

# redis install function
# default dir /usr/local/bin
function install_redis {
    [ -f "$REDIS_LOCK" ] && return

    echo "install redis..."

    # 进入源码目录并安全拉取
    cd "$SRC_DIR" || error_exit "Failed to enter dir: $SRC_DIR"
    [ ! -f "$REDIS_DIR$SRC_SUFFIX" ] && wget --no-check-certificate "$REDIS_DOWN" -O "$REDIS_DIR$SRC_SUFFIX"

    # 清理并解压
    [ -d "$REDIS_DIR" ] && rm -rf "$REDIS_DIR"
    tar -zxvf "$REDIS_DIR$SRC_SUFFIX"
    cd "$REDIS_DIR" || error_exit "Failed to enter dir: $REDIS_DIR"

    make clean > /dev/null 2>&1

    # 编译并安装，使用 jemalloc 内存分配器，减少内存碎片
    make MALLOC=jemalloc -j "$(nproc)"
    [ $? != 0 ] && error_exit "redis make err"
    make PREFIX="$INSTALL_DIR/$REDIS_DIR" install
    [ $? != 0 ] && error_exit "redis install err"

    # 建立多版本公共软链接
    [ -L "$INSTALL_DIR/redis" ] || [ -f "$INSTALL_DIR/redis" ] && rm -f "$INSTALL_DIR/redis"
    ln -sf "$INSTALL_DIR/$REDIS_DIR" "$INSTALL_DIR/redis"

    # 将核心二进制工具注入自定义全局快捷路径中
    ln -sf "$INSTALL_DIR/redis/bin/redis-server" /usr/local/bin/redis-server
    ln -sf "$INSTALL_DIR/redis/bin/redis-cli" /usr/local/bin/redis-cli
    ln -sf "$INSTALL_DIR/redis/bin/redis-benchmark" /usr/local/bin/redis-benchmark

    # 初始化并隔离生产环境配置文件
    mkdir -p "$INSTALL_DIR/redis/etc"
    mkdir -p /www/logs/redis
    mkdir -p /www/server/redis/data
    chown -R www:www /www/logs/redis
    chown -R www:www /www/server/redis/data

    # 复制并初始化 redis.conf 基础配置
    cp -f redis.conf "$INSTALL_DIR/redis/etc/redis.conf"
    sed -i 's@^protected-mode yes@protected-mode no@' "$INSTALL_DIR/redis/etc/redis.conf"
    sed -i 's@^bind 127.0.0.1@#bind 127.0.0.1@' "$INSTALL_DIR/redis/etc/redis.conf"
    sed -i 's@^# requirepass foobared@requirepass password@' "$INSTALL_DIR/redis/etc/redis.conf"
    sed -i 's@^logfile ""@logfile "/www/logs/redis/redis.log"@' "$INSTALL_DIR/redis/etc/redis.conf"
    sed -i 's@^dir ./@dir /www/server/redis/data/@' "$INSTALL_DIR/redis/etc/redis.conf"
    sed -i 's@^pidfile /var/run/redis_6379.pid@pidfile /www/server/redis/data/redis_6379.pid@' "$INSTALL_DIR/redis/etc/redis.conf"

    # 启用现代高并发 AOF 固化持久化机制，并配置高并发内存上限保护（示范设为 512MB）
    sed -i 's@^appendonly no@appendonly yes@' "$INSTALL_DIR/redis/etc/redis.conf"
    sed -i 's@^# maxmemory <bytes>@maxmemory 536870912@' "$INSTALL_DIR/redis/etc/redis.conf"
    sed -i 's@^# maxmemory-policy noeviction@maxmemory-policy volatile-lru@' "$INSTALL_DIR/redis/etc/redis.conf"

    # 复制静态 Systemd 模板，并赋予标准读取权限
    cp "$ROOT/redis.server.conf/redis.service" /etc/systemd/system/redis.service
    chmod 644 /etc/systemd/system/redis.service

    # 修正内存分配策略，防止 Redis 在做持久化 Fork 时因内存溢出被内核 OOM 强行杀死
    if ! grep -q "vm.overcommit_memory" /etc/sysctl.conf; then
        echo "vm.overcommit_memory = 1" >> /etc/sysctl.conf
        sysctl -p >/dev/null 2>&1
    fi

    # 强制禁用透明大页（Transparent Huge Pages），防止严重的内存延迟与写时复制（COW）大开销
    if [ -f /sys/kernel/mm/transparent_hugepage/enabled ]; then
        echo never > /sys/kernel/mm/transparent_hugepage/enabled
        # 确保开机自动禁用
        if ! grep -q "transparent_hugepage" /etc/rc.local; then
            echo "echo never > /sys/kernel/mm/transparent_hugepage/enabled" >> /etc/rc.local
            chmod +x /etc/rc.local
        fi
    fi

    # 注册并启动 Systemd 服务
    systemctl daemon-reload
    systemctl enable redis
    systemctl start redis

    echo  
    echo "install redis complete."
    touch "$REDIS_LOCK"
}

# install common dependency
function install_common {
    [ -f "$COMMON_LOCK" ] && return

    echo "install crb and epel..."
    # 启用 Rocky 9 的官方代码就绪库（CRB）和安装 EPEL 源
    # 很多如 oniguruma-devel 的高阶开发包都在这里面
    dnf config-manager --set-enabled crb >/dev/null 2>&1
    dnf install -y epel-release >/dev/null 2>&1
    # 强行刷新 DNF 缓存，确保系统能够立刻识别来自 EPEL 的高级开发包
    dnf makecache >/dev/null 2>&1

    echo "install dependency..."
    dnf install -y sudo wget gcc gcc-c++ make cmake autoconf automake
    [ $? != 0 ] && error_exit "common dependence install err"

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
    install_redis
}

start_install
