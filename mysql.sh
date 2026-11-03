. ./common.sh

INSTALL_DIR="/www/server"
LOCK_DIR="$ROOT/lock"
SRC_DIR="$ROOT/src"
SRC_SUFFIX=".tar.gz"
# mysql source
MYSQL_DOWN="https://cdn.mysql.com/archives/mysql-8.0/mysql-8.0.40.tar.gz"
MYSQL_DIR="mysql-8.0.40"
MYSQL_LOCK="$LOCK_DIR/mysql.lock"
# common dependency for mysql
COMMON_LOCK="$LOCK_DIR/mysql.common.lock"

# mysql install function
function install_mysql {

    [ -f "$MYSQL_LOCK" ] && return

    echo "install mysql..."

    cd "$SRC_DIR" || error_exit "Failed to enter dir: $SRC_DIR"
    [ ! -f "$MYSQL_DIR$SRC_SUFFIX" ] && wget "$MYSQL_DOWN"
    tar -zxvf "$MYSQL_DIR$SRC_SUFFIX"
    cd "$MYSQL_DIR" || error_exit "Failed to enter dir: $MYSQL_DIR"

    # 创建并进入独立的编译目录（规避污染，方便重试）
    mkdir -p build
    cd build || error_exit "Failed to enter build directory"
    # 确保 data 目录为空，确保 boost 目录路径，PREFIX 必须是绝对路径
    cmake .. \
        -DCMAKE_INSTALL_PREFIX="$INSTALL_DIR/$MYSQL_DIR" \
        -DMYSQL_DATADIR="$INSTALL_DIR/$MYSQL_DIR/data" \
        -DSYSCONFDIR="$INSTALL_DIR/etc" \
        -DMYSQL_UNIX_ADDR=/var/lib/mysql/mysql.sock \
        -DWITH_INNOBASE_STORAGE_ENGINE=1 \
        -DWITH_PARTITION_STORAGE_ENGINE=1 \
        -DWITH_FEDERATED_STORAGE_ENGINE=1 \
        -DWITH_BLACKHOLE_STORAGE_ENGINE=1 \
        -DWITH_MYISAM_STORAGE_ENGINE=1 \
        -DWITH_ARCHIVE_STORAGE_ENGINE=1 \
        -DENABLED_LOCAL_INFILE=1 \
        -DENABLE_DTRACE=0 \
        -DDEFAULT_CHARSET=utf8mb4 \
        -DDEFAULT_COLLATION=utf8mb4_general_ci \
        -DDOWNLOAD_BOOST=1 \
        -DDOWNLOAD_BOOST_TIMEOUT=1200 \
        -DWITH_BOOST=../../boost \
        -DENABLE_WERROR=OFF
    [ $? != 0 ] && error_exit "mysql configure err"
    make -j "$(nproc)"
    [ $? != 0 ] && error_exit "mysql make err"
    make install
    [ $? != 0 ] && error_exit "mysql install err"
    # 切换到源码根目录
    cd .. || error_exit "Failed to return to mysql source root directory"

    # 建立多版本公共软链接
    ln -sf "$INSTALL_DIR/$MYSQL_DIR" "$INSTALL_DIR/mysql"

    # 将全局快捷命令安全注入自定义用户 bin 目录下
    ln -sf "$INSTALL_DIR/mysql/bin/mysql" /usr/local/bin/mysql
    ln -sf "$INSTALL_DIR/mysql/bin/mysqldump" /usr/local/bin/mysqldump
    ln -sf "$INSTALL_DIR/mysql/bin/mysqlslap" /usr/local/bin/mysqlslap
    ln -sf "$INSTALL_DIR/mysql/bin/mysqladmin" /usr/local/bin/mysqladmin

    # 备份旧配置文件
    [ -f /etc/my.cnf ] && mv /etc/my.cnf /etc/my.cnf.old
    # 复制新配置文件
    [ ! -d "$INSTALL_DIR/etc" ] && mkdir "$INSTALL_DIR/etc"
    cp -f "$ROOT/mysql.conf/my.cnf" "$INSTALL_DIR/etc/my.cnf"
    ln -sf "$INSTALL_DIR/etc/my.cnf" /etc/my.cnf
    # 确保 www 目录可写
    chmod -R 755 /www
    # 添加到环境变量
    echo "export PATH=\$PATH:$INSTALL_DIR/mysql/bin" > /etc/profile.d/mysql.sh
    # 写入正确的 lib 动态链接库路径
    echo "$INSTALL_DIR/mysql/lib" > /etc/ld.so.conf.d/mysql-wdl.conf
    # 刷新并加载动态链接库
    ldconfig

    # 创建公共日志目录并赋予 mysql 用户权限
    mkdir -p /www/logs/mysql
    chown -R mysql:mysql /www/logs/mysql
    chmod 750 /www/logs/mysql
    # 创建 Socket 目录并赋予 mysql 用户权限
    mkdir -p /var/lib/mysql
    chown -R mysql:mysql /var/lib/mysql
    chmod 755 /var/lib/mysql

    # 初始化数据库
    # 确保实际版本的安装目录和数据目录权限正确
    chown -R mysql:mysql "$INSTALL_DIR/$MYSQL_DIR"
    # --initialize 设置一个随机密码到日志文件
    # --initialize-insecure 设置一个空密码的 root 用户
    # 使用实际版本路径进行精准初始化
    "$INSTALL_DIR/$MYSQL_DIR/bin/mysqld" --defaults-file=/etc/my.cnf --initialize-insecure  --user=mysql \
        --basedir="$INSTALL_DIR/$MYSQL_DIR" --datadir="$INSTALL_DIR/$MYSQL_DIR/data"

    # 复制静态 Systemd 模板，并赋予标准读取权限
    cp "$ROOT/mysql.conf/mysqld.service" /etc/systemd/system/mysqld.service
    chmod 644 /etc/systemd/system/mysqld.service

    # 注册并启动 Systemd 服务
    systemctl daemon-reload
    systemctl enable mysqld
    systemctl start mysqld

    # 稍微等待 2 秒确保本地 Socket 文件完全吐出来
    sleep 2
    # 初始化无密码后设置新密码
    /usr/local/bin/mysql -u root --socket=/var/lib/mysql/mysql.sock -e "ALTER USER 'root'@'localhost' IDENTIFIED BY 'password'; FLUSH PRIVILEGES;"

    echo
    echo "install mysql complete."
    touch "$MYSQL_LOCK"
}

# install common dependency
# mysql 8.0.x compile require boost
# mysql 8.0.x require gcc 5.3 or newer
# remove system default cmake
# mysql user:group is mysql:mysql
function install_common {
    [ -f "$COMMON_LOCK" ] && return

    echo "install crb and epel..."
    # 启用 Rocky 9 的官方代码就绪库（CRB）和安装 EPEL 源
    dnf config-manager --set-enabled crb >/dev/null 2>&1
    dnf install -y epel-release >/dev/null 2>&1
    # 强行刷新 DNF 缓存，确保系统能够立刻识别来自 EPEL 的高级开发包

    dnf makecache >/dev/null 2>&1

    echo "install dependency..."
    dnf install -y wget make cmake gcc gcc-c++ ncurses-devel openssl-devel libtirpc-devel bison \
        boost-devel rpcgen gcc-toolset-12-gcc gcc-toolset-12-gcc-c++ gcc-toolset-12-binutils \
        gcc-toolset-12-annobin-annocheck gcc-toolset-12-annobin-plugin-gcc
    [ $? != 0 ] && error_exit "common dependence install err"

    # 创建专门运行 MySQL 的系统用户和组
    # 检查 mysql 用户是否存在，不存在则精准创建
    # -d to set user home_dir=/www
    # -s to set user login shell=/sbin/nologin, you also to set /bin/bash
    if ! getent passwd mysql >/dev/null 2>&1; then
        useradd -U -d /dev/null -s /sbin/nologin -M mysql > /dev/null 2>&1
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
    install_mysql
}

start_install
