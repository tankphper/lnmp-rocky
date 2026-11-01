. ./common.sh

function install_tool {
    # install bash-completion
    dnf install -y bash-completion
    [ $? -ne 0 ] && error_exit "bash-completion install err"
    # 不需要写入任何文件，登录新终端时系统会自动加载
    if [ -f "/etc/profile.d/bash_completion.sh" ]; then
        source /etc/profile.d/bash_completion.sh
    fi
    # install composer
    [ ! -L /usr/local/bin/php ] && error_exit "Please install php first..."
    curl -sS https://getcomposer.org/installer | php
    [ $? -ne 0 ] && error_exit "Failed to download or execute composer installer"
    if [ -f "composer.phar" ]; then
        mv -f "composer.phar" /usr/local/bin/composer
        chmod +x /usr/local/bin/composer
    else
        error_exit "composer.phar not found after installer execution"
    fi
    if [ ! -f /usr/bin/php ] && [ ! -L /usr/bin/php ]; then
        ln -sf "/usr/local/bin/php" /usr/bin/php
    fi
}

install_tool
