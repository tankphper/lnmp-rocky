. ./common.sh

INSTALL_DIR="/www/server"
LOCK_DIR="$ROOT/lock"
SRC_DIR="$ROOT/src"
SRC_SUFFIX=".tar.gz"
# mysql source
MYSQL_DOWN="https://cdn.mysql.com/archives/mysql-8.0/mysql-8.0.40.tar.gz"
MYSQL_SRC="mysql-8.0.40"
MYSQL_DIR="$MYSQL_SRC"
MYSQL_LOCK="$LOCK_DIR/mysql.lock"
# cmake tool source
CMAKE_DOWN="https://cmake.org/files/v3.19/cmake-3.19.2.tar.gz"
CMAKE_SRC="cmake-3.19.2"
CMAKE_DIR="$CMAKE_SRC"
CMAKE_LOCK="$LOCK_DIR/mysql.cmake.lock"
# 1.72.0 for mysql 8.0.x
BOOST_DOWN="https://gitlab.com/lnmp-shell/lnmp-files/-/raw/master/boost_1_72_0.tar.gz"
BOOST_SRC="boost_1_72_0"
BOOST_DIR="$BOOST_SRC"
BOOST_LOCK="$LOCK_DIR/mysql.boost.lock"
# mysql-8.0.x require rpcgen
RPCGEN_DOWN="https://github.com/thkukuk/rpcsvc-proto/releases/download/v1.4.2/rpcsvc-proto-1.4.2.tar.xz"
RPCGEN_SRC="rpcsvc-proto-1.4.2"
RPCGEN_LOCK="$LOCK_DIR/mysql.rpcgen.lock"
# common dependency for mysql
COMMON_LOCK="$LOCK_DIR/mysql.common.lock"

# mysql install function
function install_mysql {

    [ -f "$MYSQL_LOCK" ] && return

    echo "install mysql..."

    cd "$SRC_DIR" || error_exit "Failed to enter dir: $SRC_DIR"
    [ ! -f "$MYSQL_SRC$SRC_SUFFIX" ] && wget "$MYSQL_DOWN"
    tar -zxvf "$MYSQL_SRC$SRC_SUFFIX"
    cd "$MYSQL_SRC" || error_exit "Failed to enter dir: $MYSQL_SRC"
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
    ln -sf "$INSTALL_DIR/$MYSQL_SRC" "$INSTALL_DIR/mysql"
    ln -sf "$INSTALL_DIR/mysql/bin/mysql" /usr/local/bin/
    ln -sf "$INSTALL_DIR/mysql/bin/mysqldump" /usr/local/bin/
    ln -sf "$INSTALL_DIR/mysql/bin/mysqlslap" /usr/local/bin/
    ln -sf "$INSTALL_DIR/mysql/bin/mysqladmin" /usr/local/bin/
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
    # 开机启动脚本
    cp "$ROOT/mysql.conf/mysqld.service" /etc/systemd/system/mysqld.service
    chmod 644 /etc/systemd/system/mysqld.service
    # 设置开机启动
    systemctl daemon-reload
    systemctl enable mysqld
    # 启动数据库
    systemctl start mysqld

    # 稍微等待 2 秒确保本地 Socket 文件完全吐出来
    sleep 2
    # 初始化无密码后设置新密码
    /usr/local/bin/mysql -u root --socket=/var/lib/mysql/mysql.sock -e "ALTER USER 'root'@'localhost' IDENTIFIED BY 'password'; FLUSH PRIVILEGES;"

    echo
    echo "install mysql complete."
    touch "$MYSQL_LOCK"
}

# cmake install function
# mysql depend cmake to compile
# cmake_dir=/usr
function install_cmake {
    [ -f "$CMAKE_LOCK" ] && return

    echo "install cmake..."
    cd "$SRC_DIR" || error_exit "Failed to enter dir: $SRC_DIR"
    [ ! -f "$CMAKE_SRC$SRC_SUFFIX" ] && wget "$CMAKE_DOWN"
    tar -zxvf "$CMAKE_SRC$SRC_SUFFIX"
    cd "$CMAKE_SRC" || error_exit "Failed to enter dir: $CMAKE_SRC"
    ./bootstrap --prefix=/usr
    [ $? != 0 ] && error_exit "cmake configure err"
    make
    [ $? != 0 ] && error_exit "cmake make err"
    make install
    [ $? != 0 ] && error_exit "cmake install err"
    cd "$SRC_DIR" || error_exit "Failed to enter dir: $SRC_DIR"
    rm -fr "$CMAKE_SRC"

    echo
    echo "install cmake complete."
    touch "$CMAKE_LOCK"
}

# boost install function
# mysql depend boost library
# cmake option -DDOWNLOAD_BOOST=1 and it will download boost auto
function install_boost {
    [ -f "$BOOST_LOCK" ] && return

    echo "install boost..."
    cd "$SRC_DIR" || error_exit "Failed to enter dir: $SRC_DIR"
    [ ! -f "$BOOST_SRC$SRC_SUFFIX" ] && wget "$BOOST_DOWN"
    tar -zxvf "$BOOST_SRC$SRC_SUFFIX"
    rm -fr "$BOOST_SRC$SRC_SUFFIX"

    echo
    echo "install boost complete."
    touch "$BOOST_LOCK"
}

# mysql-8.0.x require rpcgen
function install_rpcgen {
    [ -f "$RPCGEN_LOCK" ] && return

    echo "install rcpgen..."
    cd "$SRC_DIR" || error_exit "Failed to enter dir: $SRC_DIR"
    wget "$RPCGEN_DOWN"
    xz -d "$RPCGEN_SRC.tar.xz"
    tar -xvf "$RPCGEN_SRC.tar"
    cd "$RPCGEN_SRC" || error_exit "Failed to enter dir: $RPCGEN_SRC"
    ./configure
    [ $? != 0 ] && error_exit "rpcgen configure err"
    make
    [ $? != 0 ] && error_exit "rpcgen make err"
    make install
    [ $? != 0 ] && error_exit "rpcgen install err"
    cd "$SRC_DIR" || error_exit "Failed to enter dir: $SRC_DIR"
    rm -fr "$RPCGEN_SRC"

    echo
    echo "install rpcgen complete."
    touch "$RPCGEN_LOCK"
}

# install common dependency
# mysql 8.0.x compile require boost default dir=/usr/share/doc/boost-1.72.0
# mysql 8.0.x require gcc 5.3 or newer
# remove system default cmake
# mysql user:group is mysql:mysql
function install_common {
    [ -f "$COMMON_LOCK" ] && return
    # 启用 Rocky 9 的官方代码就绪库（CRB）和安装 EPEL 源
    dnf config-manager --set-enabled crb >/dev/null 2>&1
    dnf install -y make cmake gcc gcc-c++ ncurses-devel openssl-devel libtirpc-devel bison \
        boost-devel rpcgen
    [ $? != 0 ] && error_exit "common dependence install err"

    # 创建专门运行 MySQL 的系统用户和组
    # 检查 mysql 用户是否存在，不存在则精准创建
    if ! getent passwd mysql >/dev/null 2>&1; then
        useradd -U -d /dev/null -s /sbin/nologin -M mysql > /dev/null 2>&1
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
    install_mysql
}

start_install
