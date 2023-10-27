#!/bin/bash

# 获取本机的IP地址列表，排除 wlan0 网络接口的 IP
#local_ips=$(ip -o addr show dev wlan0 | awk '$3 == "inet" {print $4}' | cut -d '/' -f 1)
#local_ips=$(ifconfig wlan0 | grep -oP 'inet \K[\d.]+')
#echo "$local_ips"

# 获取网络接口wlan0的网段
#subnet=$(ip addr show wlan0 | grep -oP 'inet \K[\d.]+')
#subnet=$(echo "$subnet" | cut -d '.' -f 1-3)
#subnet=$(ifconfig wlan0 | grep -oP 'inet \K[\d.]+')
#subnet=$(echo "$subnet" | cut -d '.' -f 1-3)
#echo "$subnet"

# 使用ifconfig命令获取所有网络接口的信息，并将输出保存到变量output中
output=$(ifconfig)

# 使用awk来提取wlan0接口的部分信息
wlan0_info=$(echo "$output" | awk '/wlan0:/,/^$/')

# 使用grep和awk来提取wlan0接口的IP地址行
ip_line=$(echo "$wlan0_info" | grep -o 'inet [0-9.]\+')

# 使用awk来提取IP地址字段
local_ips=$(echo "$ip_line" | awk '{print $2}')

# 使用cut命令来提取IP地址的前三个字段，得到网段
subnet=$(echo "$local_ips" | cut -d '.' -f 1-3)

# 输出IP地址和网段
echo "wlan0 IP地址: $local_ips"
echo "wlan0 网段: $subnet"


# 使用parallel执行扫描任务，提取可达节点并保存到 reachable_nodes 变量中
reachable_nodes=$(seq 1 254 | parallel -j 254 '
  ip="'$subnet.'{}"
  if [ "$local_ips" != "$ip" ]; then
    if ping -c 1 -w 1 -i 0.2 "$ip" > /dev/null 2>&1; then
      echo "$ip"
    fi
  fi
')

# 构建节点列表字符串，使用逗号分隔
host_list=""
for node in $reachable_nodes; do
  if [ "$local_ips" != "$node" ]; then
    host_list="${host_list}http://$node:4001,"
  fi
done

# 去除最后一个逗号
host_list="${host_list%,}"

rqlitedpath=$(cat "rqlitedir")

rm -rf ${rqlitedpath}/data

# 打印最终命令
final_command="${rqlitedpath}/rqlited -node-id ${local_ips} -http-addr 0.0.0.0:4001 -http-adv-addr ${local_ips}:4001 -raft-adv-addr ${local_ips}:4002 -raft-addr 0.0.0.0:4002 -bootstrap-expect 1 -join ${host_list} ${rqlitedpath}/data"
echo "$final_command"

# 在screen中启动rqlite
screen -dmS rqlited $final_command

# 休眠5秒 等待集群搭建完成
sleep 5

# 使用 df 命令获取文件系统信息，并将结果存储在一个变量中
# df_output=$(df -h)

# 使用 awk 来解析 df 命令的输出并计算总可用空间（以GB为单位）
# total_available_space=0

# 创建一个临时文件用于保存 awk 的输出
# tmpfile=$(mktemp)
# echo "$df_output" | awk 'NR>1' > "$tmpfile"

# 跳过标题行并遍历每一行
# while read -r line; do
    # 提取可用空间列的数值部分（第4列）
#    available_space=$(echo "$line" | awk '{print $4}')
    
    # 获取大小单位（如K、M、G）以确定如何进行转换
#    unit=$(echo "$line" | awk '{print $4}' | grep -o '[A-Za-z]*$')
    
    # 删除大小单位，以便于计算
#    available_space=$(echo "$available_space" | sed 's/[A-Za-z]*$//')
    
    # 根据单位进行转换，将所有值转换为GB
#    if [ "$unit" = "K" ]; then
#        available_space=$(awk "BEGIN {print $available_space / 1024}")
#    elif [ "$unit" = "M" ]; then
#        available_space=$(awk "BEGIN {print $available_space / 1024 / 1024}")
#    elif [ "$unit" = "G" ]; then
        # 已经是GB单位，无需转换
#        available_space=$(echo "$available_space" | sed 's/[A-Za-z]*$//')
#    fi    
    # 纯 Bash 计算浮点数
#    total_available_space=$(awk "BEGIN {print $total_available_space + $available_space}")
# done < "$tmpfile"

# 输出总可用空间（以GB为单位）
# echo "总可用空间：$total_available_space GB"

# 删除临时文件
# rm -f "$tmpfile"

# 使用 df 命令获取 /data 分区的信息
data_partition_info=$(df -h /data)

# 使用 awk 从输出中提取剩余空间的大小（以GB为单位）
data_available_space=$(echo "$data_partition_info" | awk 'NR>1 {print $4}')

# 输出剩余空间大小
echo "数据分区（/data）的剩余空间大小：$data_available_space"

json="[\"insert into node values('${local_ips}', '${local_ips}', 4001, 'Android', 0, 1, ${data_available_space%G}, 1)\"]"

echo "${json}"

curl -XPOST 'localhost:4001/db/execute?pretty&timings' -H "Content-Type: application/json" -d "${json}" 
