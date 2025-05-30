代码功能概述

该仓库只有一个脚本 gofdipfile.sh。脚本开头定义了 Cloudflare 账户信息、需要更新的域名以及相关配置。随后脚本会根据当前系统自动选择包管理器并安装 curl、jq 等依赖。
脚本接着通过 Cloudflare API 获取每个域名的 zone_id，并检测网络环境是否能访问 ChatGPT 等站点。
之后读取指定文件夹中的 IP 地址列表，依次尝试添加到 DNS 记录中，等待 65 秒后测试是否能够访问 ChatGPT；若能访问则记录延迟并删除临时记录，否则直接删除。
将所有测试成功的 IP 按延迟排序并取前 MAX_IPS 个，最终同步到所有配置的域名的 A/AAAA 记录中。

使用方法简述

打开脚本，在开头填入自己的 Cloudflare 邮箱 x_email、Global API Key api_key，并在 hostnames=(\"...\") 中写入要更新的域名列表。

根据需要调整 FILEPATH（存放 IP 文件的目录）、country（指定国家或 FDIP）及 MAX_IPS 等参数。

确保在 FILEPATH 指定路径下存在相应的 IP 地址文件，如 FDIP/US.txt 等。

在 Linux 系统下执行 bash gofdipfile.sh。脚本会自动安装缺失的依赖，并按上述逻辑更新 Cloudflare DNS 记录。

运行结束后，会在当前目录生成 FDIP-GPT-<国家>-<时间>.txt 文件，记录成功的 IP 及其延迟。

这样即可自动筛选可用 IP 并同步到 Cloudflare，用于维持代理域名的可达性。
