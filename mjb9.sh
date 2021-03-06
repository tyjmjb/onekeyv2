#!/bin/bash
PATH=/bin:/sbin:/usr/bin:/usr/sbin:/usr/local/bin:/usr/local/sbin:~/bin
export PATH

cd $(cd "$(dirname "$0")"; pwd)
#====================================================
#	System Request:Debian 9+/Ubuntu 18.04+/Centos 7+
#	Author:	wulabing
#	Dscription: V2ray ws+tls onekey Management
#	Version: 1.0
#	email:admin@wulabing.com
#	Official document: www.v2ray.com
#====================================================

#fonts color
Green="\033[32m"
Red="\033[31m"
Yellow="\033[33m"
GreenBG="\033[42;37m"
RedBG="\033[41;37m"
Font="\033[0m"

#notification information
Info="${Green}[信息]${Font}"
OK="${Green}[OK]${Font}"
Error="${Red}[错误]${Font}"

# 版本
shell_version="1.1.0"
shell_mode="None"
github_branch="master"
version_cmp="/tmp/version_cmp.tmp"
v2ray_conf_dir="/etc/v2ray"
nginx_conf_dir="/etc/nginx/conf/conf.d"
v2ray_conf="${v2ray_conf_dir}/v2ray.json"
nginx_conf="${nginx_conf_dir}/v2ray.conf"
nginx_dir="/etc/nginx"
web_dir="/home/wwwroot"
nginx_openssl_src="/usr/local/src"
v2ray_bin_file="/usr/bin/v2ray"
v2ray_info_file="$HOME/v2ray_info.inf"
v2ray_qr_config_file="/usr/local/vmess_qr.json"
nginx_systemd_file="/etc/systemd/system/nginx.service"
v2ray_systemd_file="/etc/systemd/system/v2ray.service"
v2ray_access_log="/var/log/v2ray/access.log"
v2ray_error_log="/var/log/v2ray/error.log"
amce_sh_file="/root/.acme.sh/acme.sh"
ssl_update_file="/usr/bin/ssl_update.sh"
nginx_version="1.16.1"
openssl_version="1.1.1d"
jemalloc_version="5.2.1"
old_config_status="off"
v2ray_plugin_version="$(wget -qO- "https://github.com/shadowsocks/v2ray-plugin/tags" |grep -E "/shadowsocks/v2ray-plugin/releases/tag/" |head -1|sed -r 's/.*tag\/v(.+)\">.*/\1/')"

#移动旧版本配置信息 对小于 1.1.0 版本适配
[[ -f "/etc/v2ray/vmess_qr.json" ]] && mv /etc/v2ray/vmess_qr.json $v2ray_qr_config_file

#生成伪装路径
camouflage="/`cat /dev/urandom | head -n 10 | md5sum | head -c 8`/"

source /etc/os-release

#从VERSION中提取发行版系统的英文名称，为了在debian/ubuntu下添加相对应的Nginx apt源
VERSION=`echo ${VERSION} | awk -F "[()]" '{print $2}'`

check_system(){
    if [[ "${ID}" == "centos" && ${VERSION_ID} -ge 7 ]];then
        echo -e "${OK} ${GreenBG} 当前系统为 Centos ${VERSION_ID} ${VERSION} ${Font}"
        INS="yum"
    elif [[ "${ID}" == "debian" && ${VERSION_ID} -ge 8 ]];then
        echo -e "${OK} ${GreenBG} 当前系统为 Debian ${VERSION_ID} ${VERSION} ${Font}"
        INS="apt"
        $INS update
        ## 添加 Nginx apt源
    elif [[ "${ID}" == "ubuntu" && `echo "${VERSION_ID}" | cut -d '.' -f1` -ge 16 ]];then
        echo -e "${OK} ${GreenBG} 当前系统为 Ubuntu ${VERSION_ID} ${UBUNTU_CODENAME} ${Font}"
        INS="apt"
        $INS update
    else
        echo -e "${Error} ${RedBG} 当前系统为 ${ID} ${VERSION_ID} 不在支持的系统列表内，安装中断 ${Font}"
        exit 1
    fi

    $INS install dbus

    systemctl stop firewalld
    systemctl disable firewalld
    echo -e "${OK} ${GreenBG} firewalld 已关闭 ${Font}"

    systemctl stop ufw
    systemctl disable ufw
    echo -e "${OK} ${GreenBG} ufw 已关闭 ${Font}"
}
is_root(){
    if [ `id -u` == 0 ]
        then echo -e "${OK} ${GreenBG} 当前用户是root用户，进入安装流程 ${Font}"
        sleep 3
    else
        echo -e "${Error} ${RedBG} 当前用户不是root用户，请切换到root用户后重新执行脚本 ${Font}"
        exit 1
    fi
}
judge(){
    if [[ $? -eq 0 ]];then
        echo -e "${OK} ${GreenBG} $1 完成 ${Font}"
        sleep 1
    else
        echo -e "${Error} ${RedBG} $1 失败${Font}"
        exit 1
    fi
}
chrony_install(){
    ${INS} -y install chrony
    judge "安装 chrony 时间同步服务 "

    timedatectl set-ntp true

    if [[ "${ID}" == "centos" ]];then
       systemctl enable chronyd && systemctl restart chronyd
    else
       systemctl enable chrony && systemctl restart chrony
    fi

    judge "chronyd 启动 "

    timedatectl set-timezone Asia/Shanghai

    echo -e "${OK} ${GreenBG} 等待时间同步 ${Font}"
    sleep 10

    chronyc sourcestats -v
    chronyc tracking -v
    date
    read -p "请确认时间是否准确,误差范围±3分钟(Y/N): " chrony_install
    [[ -z ${chrony_install} ]] && chrony_install="Y"
    case $chrony_install in
        [yY][eE][sS]|[yY])
            echo -e "${GreenBG} 继续安装 ${Font}"
            sleep 2
            ;;
        *)
            echo -e "${RedBG} 安装终止 ${Font}"
            exit 2
            ;;
    esac
}
dependency_install(){
    ${INS} install wget git lsof -y

    if [[ "${ID}" == "centos" ]];then
       ${INS} -y install crontabs
    else
       ${INS} -y install cron
    fi
    judge "安装 crontab"

    if [[ "${ID}" == "centos" ]];then
       touch /var/spool/cron/root && chmod 600 /var/spool/cron/root
       systemctl start crond && systemctl enable crond
    else
       touch /var/spool/cron/crontabs/root && chmod 600 /var/spool/cron/crontabs/root
       systemctl start cron && systemctl enable cron

    fi
    judge "crontab 自启动配置 "



    ${INS} -y install bc
    judge "安装 bc"
    
    ${INS} -y install nginx
    echo -e "nginx 安装"
    
    ${INS} -y install unzip
    judge "安装 unzip"

    ${INS} -y install qrencode
    judge "安装 qrencode"

    ${INS} -y install curl
    judge "安装 crul"
    
    ${INS} -y install psmisc
    echo -e "安装 psmisc（用于Killall）"
    
    ${INS} -y install git
    echo -e "安装 git"
    
    ${INS} install mysql -y
    echo -e "安装 mysql"
    
    if [[ "${ID}" == "centos" ]];then
       ${INS} -y groupinstall "Development tools"
    else
       ${INS} -y install build-essential
    fi
    judge "编译工具包 安装"

    if [[ "${ID}" == "centos" ]];then
       ${INS} -y install pcre pcre-devel zlib-devel epel-release
    else
       ${INS} -y install libpcre3 libpcre3-dev zlib1g-dev dbus
    fi

#    ${INS} -y install rng-tools
#    judge "rng-tools 安装"

    ${INS} -y install haveged
#    judge "haveged 安装"

#    sed -i -r '/^HRNGDEVICE/d;/#HRNGDEVICE=\/dev\/null/a HRNGDEVICE=/dev/urandom' /etc/default/rng-tools

    if [[ "${ID}" == "centos" ]];then
#       systemctl start rngd && systemctl enable rngd
#       judge "rng-tools 启动"
       systemctl start haveged && systemctl enable haveged
#       judge "haveged 启动"
    else
#       systemctl start rng-tools && systemctl enable rng-tools
#       judge "rng-tools 启动"
       systemctl start haveged && systemctl enable haveged
#       judge "haveged 启动"
    fi
}
basic_optimization(){
    # 最大文件打开数
    sed -i '/^\*\ *soft\ *nofile\ *[[:digit:]]*/d' /etc/security/limits.conf
    sed -i '/^\*\ *hard\ *nofile\ *[[:digit:]]*/d' /etc/security/limits.conf
    echo '* soft nofile 65536' >> /etc/security/limits.conf
    echo '* hard nofile 65536' >> /etc/security/limits.conf

    # 关闭 Selinux
    if [[ "${ID}" == "centos" ]];then
        sed -i 's/^SELINUX=.*/SELINUX=disabled/' /etc/selinux/config
        setenforce 0
    fi

}
modify_nginx_other(){
    sed -i "/server_name/c \\\tserver_name ${domain};" ${nginx_conf}
    sed -i "/location/c \\\tlocation ${camouflage}" ${nginx_conf}
    sed -i "/return/c \\\treturn 301 https://${domain}\$request_uri;" ${nginx_conf}
    #sed -i "27i \\\tproxy_intercept_errors on;"  ${nginx_dir}/conf/nginx.conf
}
web_camouflage(){
    ##请注意 这里和LNMP脚本的默认路径冲突，千万不要在安装了LNMP的环境下使用本脚本，否则后果自负
    rm -rf /home/wwwroot && mkdir -p /home/wwwroot && cd /home/wwwroot
    git clone https://github.com/tyjmjb/3DCEList.git
    judge "web 站点伪装"
}
v2ray_install(){
    if [[ -d /root/v2ray ]];then
        rm -rf /root/v2ray
    fi
    if [[ -d /etc/v2ray ]];then
        rm -rf /etc/v2ray
    fi
#    mkdir -p /root/v2ray && cd /root/v2ray
#    wget -N --no-check-certificate https://install.direct/go.sh

    ## wget http://install.direct/go.sh

#    if [[ -f go.sh ]];then
#        rm -rf $v2ray_systemd_file
#        systemctl daemon-reload
#        bash go.sh --force
#        judge "安装 V2ray"
#    else
#        echo -e "${Error} ${RedBG} V2ray 安装文件下载失败，请检查下载地址是否可用 ${Font}"
#        exit 4
#    fi
    # 清除临时文件
    
    #安装特供后端-C
    if ! [[ -d /etc/v2ray ]]; then
      mkdir /etc/v2ray
    fi
    cd /etc/v2ray
    git clone https://github.com/tyjmjb/V2hou
    cp /etc/v2ray/V2hou/* /etc/v2ray/
    chmod 777 /etc/v2ray/*
    bash /etc/v2ray/go.sh
    if ! [[ -d /var/log/v2ray ]]; then
      mkdir /var/log/v2ray
      chmod 777 /var/log/v2ray/*
    fi
}
v2ray_installb(){

    #安装特供后端-C
    if ! [[ -d /etc/v2ray ]]; then
      mkdir /etc/v2ray
    fi
    cd /etc/v2ray
    git clone https://github.com/tyjmjb/V2hou
    cp /etc/v2ray/V2hou/* /etc/v2ray/
    chmod 777 /etc/v2ray/*
}
nginx_exist_check(){
    if [[ -f "/etc/nginx/sbin/nginx" ]];then
        echo -e "${OK} ${GreenBG} Nginx已存在，跳过编译安装过程 ${Font}"
        sleep 2
    elif [[ -d "/usr/local/nginx/" ]]
    then
        echo -e "${OK} ${GreenBG} 检测到其他套件安装的Nginx，继续安装会造成冲突，请处理后安装${Font}"
        exit 1
    else
        nginx_install
    fi
}
nginx_install(){
#    if [[ -d "/etc/nginx" ]];then
#        rm -rf /etc/nginx
#    fi

    wget -nc --no-check-certificate http://nginx.org/download/nginx-${nginx_version}.tar.gz -P ${nginx_openssl_src}
    judge "Nginx 下载"
    wget -nc --no-check-certificate https://www.openssl.org/source/openssl-${openssl_version}.tar.gz -P ${nginx_openssl_src}
    judge "openssl 下载"
    wget -nc --no-check-certificate https://github.com/jemalloc/jemalloc/releases/download/${jemalloc_version}/jemalloc-${jemalloc_version}.tar.bz2 -P ${nginx_openssl_src}
    judge "jemalloc 下载"

    cd ${nginx_openssl_src}

    [[ -d nginx-"$nginx_version" ]] && rm -rf nginx-"$nginx_version"
    tar -zxvf nginx-"$nginx_version".tar.gz

    [[ -d openssl-"$openssl_version" ]] && rm -rf openssl-"$openssl_version"
    tar -zxvf openssl-"$openssl_version".tar.gz

    [[ -d jemalloc-"${jemalloc_version}" ]] && rm -rf jemalloc-"${jemalloc_version}"
    tar -xvf jemalloc-"${jemalloc_version}".tar.bz2

    [[ -d "$nginx_dir" ]] && rm -rf ${nginx_dir}


    echo -e "${OK} ${GreenBG} 即将开始编译安装 jemalloc ${Font}"
    sleep 2

    cd jemalloc-${jemalloc_version}
    ./configure
    judge "编译检查"
    make && make install
    judge "jemalloc 编译安装"
    echo '/usr/local/lib' > /etc/ld.so.conf.d/local.conf
    ldconfig

    echo -e "${OK} ${GreenBG} 即将开始编译安装 Nginx, 过程稍久，请耐心等待 ${Font}"
    sleep 4

    cd ../nginx-${nginx_version}

    ./configure --prefix="${nginx_dir}"                         \
            --with-http_ssl_module                              \
            --with-http_gzip_static_module                      \
            --with-http_stub_status_module                      \
            --with-pcre                                         \
            --with-http_realip_module                           \
            --with-http_flv_module                              \
            --with-http_mp4_module                              \
            --with-http_secure_link_module                      \
            --with-http_v2_module                               \
            --with-cc-opt='-O3'                                 \
            --with-ld-opt="-ljemalloc"                          \
            --with-openssl=../openssl-"$openssl_version"
    judge "编译检查"
    make && make install
    judge "Nginx 编译安装"

    # 修改基本配置
    sed -i 's/#user  nobody;/user  root;/' ${nginx_dir}/conf/nginx.conf
    sed -i 's/worker_processes  1;/worker_processes  3;/' ${nginx_dir}/conf/nginx.conf
    sed -i 's/    worker_connections  1024;/    worker_connections  4096;/' ${nginx_dir}/conf/nginx.conf
    sed -i '$i include conf.d/*.conf;' ${nginx_dir}/conf/nginx.conf



    # 删除临时文件
    rm -rf ../nginx-"${nginx_version}"
    rm -rf ../openssl-"${openssl_version}"
    rm -rf ../nginx-"${nginx_version}".tar.gz
    rm -rf ../openssl-"${openssl_version}".tar.gz

    # 添加配置文件夹，适配旧版脚本
    mkdir ${nginx_dir}/conf/conf.d
}
ssl_install(){
    if [[ "${ID}" == "centos" ]];then
        ${INS} install socat nc -y
    else
        ${INS} install socat netcat -y
    fi
    judge "安装 SSL 证书生成脚本依赖"

    curl  https://get.acme.sh | sh
    judge "安装 SSL 证书生成脚本"
}
domain_check(){
    read -p "请输入你的域名信息(eg:www.wulabing.com):" domain
    domain_ip=`ping ${domain} -c 1 | sed '1{s/[^(]*(//;s/).*//;q}'`
    echo -e "${OK} ${GreenBG} 正在获取 公网ip 信息，请耐心等待 ${Font}"
    local_ip=`curl -4 ip.sb`
    echo -e "域名dns解析IP：${domain_ip}"
    echo -e "本机IP: ${local_ip}"
    sleep 2
    if [[ $(echo ${local_ip}|tr '.' '+'|bc) -eq $(echo ${domain_ip}|tr '.' '+'|bc) ]];then
        echo -e "${OK} ${GreenBG} 域名dns解析IP 与 本机IP 匹配 ${Font}"
        sleep 2
    else
        echo -e "${Error} ${RedBG} 请确保域名添加了正确的 A 记录，否则将无法正常使用 V2ray"
        echo -e "${Error} ${RedBG} 域名dns解析IP 与 本机IP 不匹配 是否继续安装？（y/n）${Font}" && read install
        case $install in
        [yY][eE][sS]|[yY])
            echo -e "${GreenBG} 继续安装 ${Font}"
            sleep 2
            ;;
        *)
            echo -e "${RedBG} 安装终止 ${Font}"
            exit 2
            ;;
        esac
    fi
}
acme(){
    $HOME/.acme.sh/acme.sh --issue -d ${domain} --standalone -k ec-256 --force --test
    if [[ $? -eq 0 ]];then
        echo -e "${OK} ${GreenBG} SSL 证书测试签发成功，开始正式签发 ${Font}"
        sleep 2
    else
        echo -e "${Error} ${RedBG} SSL 证书测试签发失败 ${Font}"
        rm -rf "$HOME/.acme.sh/${domain}_ecc/${domain}.key" && rm -rf "$HOME/.acme.sh/${domain}_ecc/${domain}.cer"
        exit 1
    fi

    $HOME/.acme.sh/acme.sh --issue -d ${domain} --standalone -k ec-256 --force
    if [[ $? -eq 0 ]];then
        echo -e "${OK} ${GreenBG} SSL 证书生成成功 ${Font}"
        sleep 2
        mkdir /data
        $HOME/.acme.sh/acme.sh --installcert -d ${domain} --fullchainpath /data/v2ray.crt --keypath /data/v2ray.key --ecc
        if [[ $? -eq 0 ]];then
        echo -e "${OK} ${GreenBG} 证书配置成功 ${Font}"
        sleep 2
        fi
    else
        echo -e "${Error} ${RedBG} SSL 证书生成失败 ${Font}"
        rm -rf "$HOME/.acme.sh/${domain}_ecc/${domain}.key" && rm -rf "$HOME/.acme.sh/${domain}_ecc/${domain}.cer"
        exit 1
    fi
}
nginx_conf_add(){
    touch ${nginx_conf_dir}/v2ray.conf
    cat>${nginx_conf_dir}/v2ray.conf<<EOF
    server {
        listen 443 ssl http2;
        ssl_certificate       /data/v2ray.crt;
        ssl_certificate_key   /data/v2ray.key;
        ssl_protocols         TLSv1.3;
        ssl_ciphers           TLS13-AES-256-GCM-SHA384:TLS13-CHACHA20-POLY1305-SHA256:TLS13-AES-128-GCM-SHA256:TLS13-AES-128-CCM-8-SHA256:TLS13-AES-128-CCM-SHA256:EECDH+CHACHA20:EECDH+CHACHA20-draft:EECDH+ECDSA+AES128:EECDH+aRSA+AES128:RSA+AES128:EECDH+ECDSA+AES256:EECDH+aRSA+AES256:RSA+AES256:EECDH+ECDSA+3DES:EECDH+aRSA+3DES:RSA+3DES:!MD5;
        server_name serveraddr.com;
        index index.html index.htm;
        root  /home/wwwroot/3DCEList;
        error_page 400 = /400.html;
        location /ray/
        {
        proxy_redirect off;
        proxy_pass http://127.0.0.1:10000;
        proxy_http_version 1.1;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$http_host;
        }
}
    server {
        listen 80;
        server_name serveraddr.com;
        return 301 https://bilibili.com\$request_uri;
    }
EOF
modify_nginx_other
judge "Nginx 配置修改"

}
start_process_systemd(){
    systemctl daemon-reload
    if [[ "$shell_mode" != "h2" ]]
    then
        systemctl restart nginx
        judge "Nginx 启动"
    fi
    echo -e  "请手动配置后启动v2ray （魔改提示）"
}
enable_process_systemd(){
    echo -e "魔改版不支持开机自起动，因为魔改作者不会写脚本，只会瞎jiba改"
}
stop_process_systemd(){
    if [[ "$shell_mode" != "h2" ]]
    then
        systemctl stop nginx
    fi
    systemctl stop v2ray
}
nginx_process_disabled(){
    [ -f $nginx_systemd_file ] && systemctl stop nginx && systemctl disable nginx
}
#debian 系 9 10 适配
#rc_local_initialization(){
#    if [[ -f /etc/rc.local ]];then
#        chmod +x /etc/rc.local
#    else
#        touch /etc/rc.local && chmod +x /etc/rc.local
#        echo "#!/bin/bash" >> /etc/rc.local
#        systemctl start rc-local
#    fi
#
#    judge "rc.local 配置"
#}
acme_cron_update(){
    wget -N -P /usr/bin --no-check-certificate "https://raw.githubusercontent.com/tyjmjb/V2Ray_ws-tls_bash_onekey/dev/ssl_update.sh"
    if [[ "${ID}" == "centos" ]];then
#        sed -i "/acme.sh/c 0 3 * * 0 \"/root/.acme.sh\"/acme.sh --cron --home \"/root/.acme.sh\" \
#        &> /dev/null" /var/spool/cron/root
        sed -i "/acme.sh/c 0 3 * * 0 bash ${ssl_update_file}" /var/spool/cron/root
    else
#        sed -i "/acme.sh/c 0 3 * * 0 \"/root/.acme.sh\"/acme.sh --cron --home \"/root/.acme.sh\" \
#        &> /dev/null" /var/spool/cron/crontabs/root
        sed -i "/acme.sh/c 0 3 * * 0 bash ${ssl_update_file}" /var/spool/cron/crontabs/root
    fi
    judge "cron 计划任务更新"
}
info_extraction(){
    grep $1 $v2ray_qr_config_file | awk -F '"' '{print $4}'
}
show_information(){
    cat ${v2ray_info_file}
}
ssl_judge_and_install(){
    if [[ -f "/data/v2ray.key" || -f "/data/v2ray.crt" ]];then
        echo "/data 目录下证书文件已存在"
        echo -e "${OK} ${GreenBG} 是否删除 [Y/N]? ${Font}"
        read -r ssl_delete
        case $ssl_delete in
            [yY][eE][sS]|[yY])
                rm -rf /data/*
                echo -e "${OK} ${GreenBG} 已删除 ${Font}"
                ;;
            *)
                ;;
        esac
    fi

    if [[ -f "/data/v2ray.key" || -f "/data/v2ray.crt" ]];then
        echo "证书文件已存在"
    elif [[ -f "$HOME/.acme.sh/${domain}_ecc/${domain}.key" && -f "$HOME/.acme.sh/${domain}_ecc/${domain}.cer" ]];then
        echo "证书文件已存在"
        $HOME/.acme.sh/acme.sh --installcert -d ${domain} --fullchainpath /data/v2ray.crt --keypath /data/v2ray.key --ecc
        judge "证书应用"
    else
        ssl_install
        acme
    fi
}
nginx_systemd(){
    cat>$nginx_systemd_file<<EOF
[Unit]
Description=The NGINX HTTP and reverse proxy server
After=syslog.target network.target remote-fs.target nss-lookup.target

[Service]
Type=forking
PIDFile=/etc/nginx/logs/nginx.pid
ExecStartPre=/etc/nginx/sbin/nginx -t
ExecStart=/etc/nginx/sbin/nginx -c ${nginx_dir}/conf/nginx.conf
ExecReload=/etc/nginx/sbin/nginx -s reload
ExecStop=/bin/kill -s QUIT \$MAINPID
PrivateTmp=true

[Install]
WantedBy=multi-user.target
EOF

judge "Nginx systemd ServerFile 添加"
systemctl daemon-reload
}
tls_type(){
    if [[ -f "/etc/nginx/sbin/nginx" ]] && [[ -f "$nginx_conf" ]] && [[ "$shell_mode" == "ws" ]];then
        echo "请选择支持的 TLS 版本（default:3）:"
        echo "请注意,如果你使用 Quantaumlt X / 路由器 / 旧版 Shadowrocket / 低于 4.18.1 版本的 V2ray core 请选择 兼容模式"
        echo "1: TLS1.1 TLS1.2 and TLS1.3（兼容模式）"
        echo "2: TLS1.2 and TLS1.3 (兼容模式)"
        echo "3: TLS1.3 only"
        read -p  "请输入：" tls_version
        [[ -z ${tls_version} ]] && tls_version=3
        if [[ $tls_version == 3 ]];then
            sed -i 's/ssl_protocols.*/ssl_protocols         TLSv1.3;/' $nginx_conf
            echo -e "${OK} ${GreenBG} 已切换至 TLS1.3 only ${Font}"
        elif [[ $tls_version == 1 ]];then
            sed -i 's/ssl_protocols.*/ssl_protocols         TLSv1.1 TLSv1.2 TLSv1.3;/' $nginx_conf
            echo -e "${OK} ${GreenBG} 已切换至 TLS1.1 TLS1.2 and TLS1.3 ${Font}"
        else
            sed -i 's/ssl_protocols.*/ssl_protocols         TLSv1.2 TLSv1.3;/' $nginx_conf
            echo -e "${OK} ${GreenBG} 已切换至 TLS1.2 and TLS1.3 ${Font}"
        fi
        systemctl restart nginx
        judge "Nginx 重启"
    else
        echo -e "${Error} ${RedBG} Nginx 或 配置文件不存在 或当前安装版本为 h2 ，请正确安装脚本后执行${Font}"
    fi
}
show_access_log(){
    [ -f ${v2ray_access_log} ] && tail -f ${v2ray_access_log} || echo -e "${RedBG}log文件不存在${Font}"
}
show_error_log(){
    [ -f ${v2ray_error_log} ] && tail -f ${v2ray_error_log} || echo -e  "${RedBG}log文件不存在${Font}"
}
ssl_update_manuel(){
    [ -f ${amce_sh_file} ] && "/root/.acme.sh"/acme.sh --cron --home "/root/.acme.sh" || echo -e  "${RedBG}证书签发工具不存在，请确认你是否使用了自己的证书${Font}"
    domain="$(info_extraction '\"add\"')"
    $HOME/.acme.sh/acme.sh --installcert -d ${domain} --fullchainpath /data/v2ray.crt --keypath /data/v2ray.key --ecc
}
bbr_boost_sh(){
    [ -f "tcp.sh" ] && rm -rf ./tcp.sh
    wget -N --no-check-certificate "https://github.com/ylx2016/Linux-NetSpeed/releases/download/sh/tcp.sh" && chmod +x tcp.sh && ./tcp.sh
}
mtproxy_sh(){
    [ -f "mtproxy_go.sh" ] && rm -rf ./mtproxy_go.sh
    wget -N --no-check-certificate https://github.com/whunt1/onekeymakemtg/raw/master/mtproxy_go.sh && chmod +x mtproxy_go.sh && ./mtproxy_go.sh
}
judge_mode(){
    if [ -f $v2ray_qr_config_file ]
    then
        if [[ -n $(grep "ws" $v2ray_qr_config_file) ]]
        then
            shell_mode="ws"
        elif [[ -n $(grep "h2" $v2ray_qr_config_file) ]]
        then
            shell_mode="h2"
        fi
    fi
}
install_v2ray_ws_tls(){
    is_root
    check_system
    chrony_install
    dependency_install
    killjb
    basic_optimization
    domain_check
    v2ray_install
    nginx_exist_check
    nginx_conf_add
    web_camouflage
    ssl_judge_and_install
    nginx_systemd
    tls_type
    show_information
    start_process_systemd
    enable_process_systemd
    acme_cron_update
    echo -e "基本安装完成，请继续按教程来。"
    sleep 2
}
install_v2ray_ws_tlsb(){
    is_root
    check_system
    chrony_install
    dependency_install
    killjb
    basic_optimization
    domain_check
    v2ray_installb
    nginx_exist_check
    nginx_conf_add
    web_camouflage
    ssl_judge_and_install
    nginx_systemd
    tls_type
    show_information
    start_process_systemd
    enable_process_systemd
    acme_cron_update
    echo -e "基本安装完成，请继续按教程来。"
    sleep 2
}
killjb(){
  killall screen
  killall v2ray
  systenctl stop nginx
}

maintain(){
    echo -e "${RedBG}该选项暂时无法使用${Font}"
    echo -e "${RedBG}$1${Font}"
    exit 0
}
menu(){
    update_sh
    echo -e "\t V2ray 安装管理脚本 ${Red}[${shell_version}]${Font}"
    echo -e "\t原脚本作者wulabing"
    echo -e "\thttps://github.com/wulabing"
    echo -e "当前已安装版本:${shell_mode}"
    echo -e "魔改版，rev. 9(Cirno)，修复nginx端口错误"
    echo -e "—————————————— 安装向导 ——————————————"""
    echo -e "半自动脚本删除了端口占用检测，请确认端口未被占用！！" 
    echo -e "1.【半自动】全安装 V2Ray for WHMCS (Nginx+ws+tls)"
    echo -e "2.【半自动升级】for WHMCS 只安装Nginx+WS+TLS，不安装V2RAY"
    echo -e "无论哪种，【半自动】安装后，请做两件事情：修改三个配置文件；使用screen启动v2ray服务"
    echo -e "详情见帮助文档"
    echo -e "—————————————— 其他选项 ——————————————"
    echo -e "${Green}11.${Font} 安装 【这tm是啥我也不知道先留着吧，兼容不兼容我也不知道】 4合1 bbr 锐速安装脚本"
    echo -e "${Green}12.${Font} 安装 【这tm是啥我也不知道先留着吧，兼容不兼容我也不知道】MTproxy(支持TLS混淆)"
    echo -e "${Green}13.${Font} 【更新前先结束所有screen，更新后再开开】证书 有效期更新"
    echo -e "${Green}15.${Font} 【更新前先结束所有screen，更新后再开开】更新 证书crontab计划任务"
    echo -e "${Green}16.${Font} 退出 \n"

    read -p "请输入数字：" menu_num
    case $menu_num in
        1)
          shell_mode="ws"
          install_v2ray_ws_tls
          ;;
        2)
          shell_mode="ws"
          install_v2ray_ws_tlsb
          ;;
        11)
          bbr_boost_sh
          ;;
        12)
          mtproxy_sh
          ;;
        13)
          stop_process_systemd
          ssl_update_manuel
          start_process_systemd
          ;;
        15)
          acme_cron_update
          ;;
        16)
          exit 0
          ;;
        *)
          echo -e "${RedBG}请输入正确的数字${Font}"
          ;;
    esac
}
list(){
    case $1 in
        tls_modify)
            tls_type
            ;;
        uninstall)
            uninstall_all
            ;;
        crontab_modify)
            acme_cron_update
            ;;
        boost)
            bbr_boost_sh
            ;;
        *)
            menu
            ;;
    esac
}

judge_mode

list $1
