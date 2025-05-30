#############################设置API代理网址 有时候国内API无法链接无法下载时使用################################
# 代理网址建议用自己的，随时可能失效
DL=""
##################################################账号设置######################################################
# --cloudflare账号邮箱--
x_email=
#
# --Global API Key--
# --到你托管的域名--右下角“获取您的API令牌”--Global API Key查看
api_key=
#
# --挂载的完整域名，支持同账号下的多域名，需保证第一个域名是你目前连的workers的反代域名--
# --要是不懂就老老实实填一个域名就好--
#	示例：("www.dfsgsdg.com" "www.wrewstdzs.cn")
hostnames=("")
#################################################反代设置#######################################################
# --识别后的结果文件夹名称--
FILEPATH="FDIP"
# --是否只更新干净IP，true，false，先确认自己的环境是否有对应国家的干净IP--
# --白嫖的反代包干净的可用IP近乎没有，建议false不要改--
cleanip="false"
# --选择更新到DNS记录的国家，需确认自己环境能跑出的国家，不要用HK，无法反代GPT--
# --可以先跑一次之后到文件夹下查看具体有哪些国家，个人建议US，相对稳定--
# --就算文件夹下有对应国家也不一定就是有效反代，选择IP较多的国家比较好--
# --如果你对国家没有要求，可以直接填入"FDIP"或"FDIPC"，C是纯净IP，不一定有有效的--
country="FDIP"
#
# --选择更新到DNS记录的IP数量--
# --虽然提供了这个功能，但并不建议挂载多IP，会导致各种网络体验差--
MAX_IPS=1
#####################可能需要以下几个依赖，如果无法自动安装就手动自行安装########################
DEPENDENCIES=("curl" "bash" "jq" "wget" "unzip" "tar" "sed" "grep")
#################################################################################################
# 检测发行版及其包管理器
if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS=$NAME
    case $OS in
        "Ubuntu"|"Debian"|"Armbian")
            PKG_MANAGER="apt-get"
            UPDATE_CMD="apt-get update"
            INSTALL_CMD="apt-get install -y"
            CHECK_CMD="dpkg -s"
            ;;
        "CentOS"|"Red Hat Enterprise Linux")
            PKG_MANAGER="yum"
            UPDATE_CMD="yum update -y"
            INSTALL_CMD="yum install -y"
            CHECK_CMD="rpm -q"
            ;;
        "Fedora")
            PKG_MANAGER="dnf"
            UPDATE_CMD="dnf update -y"
            INSTALL_CMD="dnf install -y"
            CHECK_CMD="rpm -q"
            ;;
        "Arch Linux")
            PKG_MANAGER="pacman"
            UPDATE_CMD="pacman -Syu"
            INSTALL_CMD="pacman -S --noconfirm"
            CHECK_CMD="pacman -Qi"
            ;;
        "OpenWrt")
            PKG_MANAGER="opkg"
            UPDATE_CMD="opkg update"
            INSTALL_CMD="opkg install"
            CHECK_CMD="opkg list-installed"
            ;;
        *)
            echo "Unsupported Linux distribution: $OS"
            exit 1
            ;;
    esac
else
    echo "Cannot detect Linux distribution."
    exit 1
fi

# 更新包管理器数据库
echo "Updating package database..."
$UPDATE_CMD

# 检测CPU架构
CPU_ARCH=$(uname -m)
echo "CPU Architecture: $CPU_ARCH"

# 根据CPU架构执行特定操作
case $CPU_ARCH in
    "x86_64"|"amd64")
        echo "Running on an AMD64/x86_64 architecture"
        # 针对AMD64/x86_64架构的操作
        ;;
    "armv7l"|"armhf")
        echo "Running on an ARMv7 architecture"
        # 针对ARMv7架构的操作
        ;;
    "aarch64"|"arm64")
        echo "Running on an ARM64 architecture"
        # 针对ARM64架构的操作
        ;;
    *)
        echo "Unsupported CPU architecture: $CPU_ARCH"
        exit 1
        ;;
esac

# 函数：检测依赖项是否已安装
function is_installed {
    case $PKG_MANAGER in
        "apt-get")
            dpkg -s $1 &> /dev/null
            ;;
        "yum"|"dnf")
            rpm -q $1 &> /dev/null
            ;;
        "pacman")
            pacman -Qi $1 &> /dev/null
            ;;
        "opkg")
            opkg list-installed | grep $1 &> /dev/null
            ;;
        *)
            echo "Unsupported package manager: $PKG_MANAGER"
            exit 1
            ;;
    esac
    return $?
}

# 安装依赖项
for DEP in "${DEPENDENCIES[@]}"; do
    echo "Checking if $DEP is installed..."
    if is_installed $DEP; then
        echo "$DEP is already installed."
    else
        echo "Installing $DEP..."
        $INSTALL_CMD $DEP
    fi
done

echo "All dependencies installed successfully."
###################################检查账号及现有反代状态########################################
# 获取区域ID
get_zone_id() {
    local hostname=$1
    curl -s -X GET "https://api.cloudflare.com/client/v4/zones?name=$(echo ${hostname} | cut -d "." -f 2-)" -H "X-Auth-Email: $x_email" -H "X-Auth-Key: $api_key" -H "Content-Type: application/json" | jq -r '.result[0].id'
}

# 获取并检查zone_id
for hostname in "${hostnames[@]}"; do
    ZONE_ID=$(get_zone_id "$hostname")

    if [ -z "$ZONE_ID" ]; then
        echo "账号登陆失败，域名: $hostname，检查账号信息"
        exit 1;
    else
        echo "账号登陆成功，域名: $hostname"
    fi
done

# 检查反代及网络环境
gpt_test=$(curl -i -s --connect-timeout 5 --max-time 5 "https://chatgpt.com")
speed_test=$(curl -i -s --connect-timeout 5 --max-time 5 -o /dev/null -w "%{http_code}" "https://www.speedtest.net")
youtube_test=$(curl -i -s --connect-timeout 5 --max-time 5 -o /dev/null -w "%{http_code}" "https://www.youtube.com")
if [ "$speed_test" -eq 200 ] && echo "$gpt_test" | grep -qE "chatgpt.com" && ! echo "$gpt_test" | grep -qE "cf.errors.css"; then
    latency=$(curl -o /dev/null --connect-timeout 5 -s -w '%{time_total}' "https://chatgpt.com")
    echo "反代域名正常，GPT访问延迟为 $latency 秒，不需要更新，脚本停止"
    exit 1
fi
if [ "$youtube_test" -eq 200 ]; then
    echo "反代域名失效，开始脚本"
else
    echo "重要！！！请在代理（翻墙）环境下运行此脚本，否则此脚本无效。"
    echo "重要！！！请使用自己的 CF Worker 或 Pages 的代理环境，并使 proxyip 指向自己打算更新的反代域名，否则此脚本无效。"
    echo "脚本停止"
    exit 1
fi
###################################################################################################
echo "================================提取反代IP等待更新DNS===================================="
# 读取反代IP文件
if [ "$cleanip" = "true" ]; then
    test_input_file="$FILEPATH/C/${country}.txt"
    else
    test_input_file="$FILEPATH/${country}.txt"
fi
awk '{ sub(/,.*/, ""); if ($0 ~ /^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$/) { split($0, octets, "."); if (octets[1] < 256 && octets[2] < 256 && octets[3] < 256 && octets[4] < 256 && !seen[$0]++) print $0 } }' $test_input_file > temp.txt && mv temp.txt $test_input_file
output_file="FDIP-GPT-${country}-$(date +%Y-%m-%d-%H-%M-%S).txt"
> "$output_file"
########################################删除并更新DNS记录############################################
echo "==================================删除并更新DNS记录======================================"
# 查询A和AAAA记录的函数
query_records() {
    local zone_id=$1
    local record_type=$2
    local hostname=$3
    curl -s \
        -H "X-Auth-Email: $x_email" \
        -H "X-Auth-Key: $api_key" \
        -H "Content-Type: application/json" \
        "https://api.cloudflare.com/client/v4/zones/$zone_id/dns_records?type=$record_type&name=$hostname&per_page=100&order=type&direction=desc&match=all" |
        jq -r '.result[] | select(.proxied == false) | "\(.id) \(.name) \(.content)"'
}

# 删除记录的函数
delete_record() {
    local zone_id=$1
    local record_id=$2
    local record_name=$3
    local record_content=$4
    response=$(curl -s -o /dev/null -w "%{http_code}" -X DELETE \
        -H "X-Auth-Email: $x_email" \
        -H "X-Auth-Key: $api_key" \
        -H "Content-Type: application/json" \
        "https://api.cloudflare.com/client/v4/zones/$zone_id/dns_records/$record_id")
    if [ "$response" -eq 200 ]; then
        echo "$record_name的DNS记录[$record_content]已成功删除"
    else
        echo "$record_name的DNS记录[$record_content]删除失败"
    fi
}

# 添加记录的函数
add_record() {
    local zone_id=$1
    local ip=$2
    local record_type=$3
    response=$(curl -s -o /dev/null -w "%{http_code}" -X POST \
        -H "X-Auth-Email: $x_email" \
        -H "X-Auth-Key: $api_key" \
        -H "Content-Type: application/json" \
        --data "{\"type\":\"$record_type\",\"name\":\"$hostname\",\"content\":\"$ip\",\"ttl\":60,\"proxied\":false}" \
        "https://api.cloudflare.com/client/v4/zones/$zone_id/dns_records")
    if [ "$response" -eq 200 ]; then
        echo "$hostname的DNS记录[$ip]已成功添加"
        return 0
    else
        echo "$hostname的DNS记录[$ip]添加失败"
        return 1
    fi
}

# 对数组按延迟排序的函数
sort_by_latency() {
    local -n arr=$1
    for ((i = 0; i < ${#arr[@]}; i++)); do
        for ((j = i + 1; j < ${#arr[@]}; j++)); do
            if awk "BEGIN {exit !(${arr[i]##*,} > ${arr[j]##*,})}"; then
                temp=${arr[i]}
                arr[i]=${arr[j]}
                arr[j]=$temp
            fi
        done
    done
}

# 处理 DNS 记录的函数
process_dns_records() {
    local hostname=$1
    local zone_id=$2
    local max_ips=$3
    
    echo "正在添加新的DNS记录并测试连通性"
    successful_ips=()
    while IFS= read -r ip; do
        if [[ $ip =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
            record_type="A"
        elif [[ $ip =~ ^[0-9a-fA-F:]+$ ]]; then
            record_type="AAAA"
        else
            echo "无效的IP地址：$ip"
            continue
        fi

        if add_record "$zone_id" "$ip" "$record_type"; then
            echo "等待65秒后测试连通性"
            sleep 65
            gpt_test=$(curl -i -s --connect-timeout 5 --max-time 5 "https://chatgpt.com")
            speed_test=$(curl -i -s --connect-timeout 5 --max-time 5 -o /dev/null -w "%{http_code}" "https://www.speedtest.net")
            if [ "$speed_test" -eq 200 ] && echo "$gpt_test" | grep -qE "chatgpt.com" && ! echo "$gpt_test" | grep -qE "cf.errors.css"; then
                latency=$(curl -o /dev/null --connect-timeout 5 -s -w '%{time_total}' "https://chatgpt.com")
                echo "$ip 的GPT连通性测试正常，访问延迟为 $latency 秒，继续测试下一个IP。"
                successful_ips+=("$ip,$latency")
                # 删除临时记录
                query_records "$zone_id" "$record_type" "$hostname" | while read -r record_id record_name record_content; do
                    if [[ "$record_content" == "$ip" ]]; then
                        delete_record "$zone_id" "$record_id" "$record_name" "$record_content"
                    fi
                done
            else
                echo "$ip 的GPT连通性测试失败，删除该记录并尝试下一个IP。"
                query_records "$zone_id" "$record_type" "$hostname" | while read -r record_id record_name record_content; do
                    if [[ "$record_content" == "$ip" ]]; then
                        delete_record "$zone_id" "$record_id" "$record_name" "$record_content"
                    fi
                done
            fi
        fi
    done < "$test_input_file"
    
    # 处理成功的IP地址，根据max_ips限制添加DNS记录
    if [ ${#successful_ips[@]} -ne 0 ]; then
        sort_by_latency successful_ips
        final_ips=("${successful_ips[@]:0:max_ips}")
        for ip_latency in "${final_ips[@]}"; do
            ip=$(echo "$ip_latency" | awk -F',' '{print $1}')
            if [[ $ip =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
                record_type="A"
            elif [[ $ip =~ ^[0-9a-fA-F:]+$ ]]; then
                record_type="AAAA"
            fi
            add_record "$zone_id" "$ip" "$record_type"
        done
    else
        echo "没有合适的有效IP，请手动检查IP"
    fi
}

# 删除第一个域名的DNS记录
if [ "${#hostnames[@]}" -gt 0 ]; then
    hostname="${hostnames[0]}"
    ZONE_ID=$(get_zone_id "$hostname")
    for record_type in A AAAA; do
        echo "正在删除 $hostname 的 $record_type 记录..."
        query_records "$ZONE_ID" "$record_type" "$hostname" | while read -r record_id record_name record_content; do
            delete_record "$ZONE_ID" "$record_id" "$record_name" "$record_content"
        done
    done
fi

# 处理第一个域名
first_hostname="${hostnames[0]}"
first_zone_id=$(get_zone_id "$first_hostname")

if [ -n "$first_zone_id" ]; then
    process_dns_records "$first_hostname" "$first_zone_id" "$MAX_IPS"
else
    echo "第一个域名 ($first_hostname) 的区域ID获取失败。"
fi

# 将成功的IP和延迟写入txt文件
if [ ${#successful_ips[@]} -ne 0 ]; then
    sort_by_latency successful_ips
    for ip_latency in "${successful_ips[@]}"; do
        echo "$ip_latency" >> "$output_file"
    done
fi

# 删除全部域名DNS记录
for hostname in "${hostnames[@]}"; do
    ZONE_ID=$(get_zone_id "$hostname")
    for record_type in A AAAA; do
        echo "正在删除 $hostname 的 $record_type 记录..."
        query_records "$ZONE_ID" "$record_type" "$hostname" | while read -r record_id record_name record_content; do
            delete_record "$ZONE_ID" "$record_id" "$record_name" "$record_content"
        done
    done
done

# 同步更新到所有域名
for hostname in "${hostnames[@]}"; do
    ZONE_ID=$(get_zone_id "$hostname")

    if [ ${#final_ips[@]} -ne 0 ]; then
        echo "有 ${#final_ips[@]} 个有效IP，开始更新最终DNS记录"
        for ip_latency in "${final_ips[@]}"]; do
            ip=$(echo "$ip_latency" | awk -F',' '{print $1}')

            if [[ $ip =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
                record_type="A"
            elif [[ $ip =~ ^[0-9a-fA-F:]+$ ]]; then
                record_type="AAAA"
            fi
            add_record "$ZONE_ID" "$ip" "$record_type"
        done
        echo "反代域名 $hostname 更新完成，已成功添加 ${#final_ips[@]} 个IP地址。"
    else
        echo "反代域名 $hostname 更新失败，没有合适的有效IP，请手动检查IP吧 T_T"
    fi
done
