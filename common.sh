ROOT=$(pwd)
CPUS=$(grep -c processor /proc/cpuinfo)
grep -q "release 7" /etc/redhat-release && VERS=7 || VERS=0
grep -q "release 8" /etc/redhat-release && VERS=8
grep -q "release 9" /etc/redhat-release && VERS=9
echo "ROOT:$ROOT"
echo "CPUS:$CPUS"
echo "VERS:$VERS"

# V1 > V2
function version_gt() { test "$(echo "$@" | tr " " "\n" | sort -V | head -n 1)" != "$1"; }
# V1 >= V2
function version_ge() { test "$(echo "$@" | tr " " "\n" | sort -rV | head -n 1)" == "$1"; }
# V1 <= V2
function version_le() { test "$(echo "$@" | tr " " "\n" | sort -V | head -n 1)" == "$1"; }
# V1 < V2
function version_lt() { test "$(echo "$@" | tr " " "\n" | sort -rV | head -n 1)" != "$1"; }

# install error function
function error_exit {
    echo >&2
    # 使用红色高显字体打印错误文本
    echo -e "\033[31m[ERROR] $1\033[0m" >&2
    echo >&2
    # 返回 1 状态码，确保全自动化流水线收到明确的失败熔断信号
    exit 1
}
