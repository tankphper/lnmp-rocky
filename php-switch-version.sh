. ./common.sh

PHP_SWT_VER=${1:-""}
if [ -z "$PHP_SWT_VER" ]; then
    echo "错误：请传入要切换的 PHP 版本号，例如：8.3.36"
    exit 1
fi

# 获取旧版本号
PHP_OLD_VER=$("/www/server/php/bin/php-config" --version)

# 检查目标要切换的 PHP 物理目录是否存在，不存在则当场熔断，防止指错死链接
if [ ! -d "/www/server/php-$PHP_SWT_VER" ]; then
    error_exit "物理目标目录 /www/server/php-$PHP_SWT_VER 不存在，请先编译该版本"
fi

ln -sf "/www/server/php-$PHP_SWT_VER/bin/php" /usr/local/bin/php
ln -sf "/www/server/php-$PHP_SWT_VER/bin/phpize" /usr/local/bin/phpize
ln -sf "/www/server/php-$PHP_SWT_VER/bin/php-config" /usr/local/bin/php-config
ln -sf "/www/server/php-$PHP_SWT_VER/sbin/php-fpm" /usr/local/sbin/php-fpm

# 符号链接强行覆盖
ln -snf "/www/server/php-$PHP_SWT_VER" /www/server/php

systemctl daemon-reload
systemctl restart php-fpm
[ $? != 0 ] && error_exit "php-fpm 服务重启可能遇到了阻碍，请检查 systemctl status php-fpm"

# 获取新版本号
PHP_NEW_VER=$("/www/server/php/bin/php-config" --version)

echo "=================================================="
echo "PHP 新版本切换成功"
echo "PHP_SWT_VER: $PHP_SWT_VER"
echo "PHP_OLD_VER: $PHP_OLD_VER"
echo "PHP_NEW_VER: $PHP_NEW_VER"
echo "=================================================="
