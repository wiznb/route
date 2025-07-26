#!/bin/bash

# 注册路由表
grep -q "100 eth0_table" /etc/iproute2/rt_tables || echo "100 eth0_table" >> /etc/iproute2/rt_tables
grep -q "200 eth1_table" /etc/iproute2/rt_tables || echo "200 eth1_table" >> /etc/iproute2/rt_tables

# 接口映射
declare -A GWS=( ["eth0"]="10.7.0.1" ["eth1"]="10.8.0.1" )
declare -A NETS=( ["eth0"]="10.7.0.0/23" ["eth1"]="10.8.0.0/22" )
declare -A TABLES=( ["eth0"]="eth0_table" ["eth1"]="eth1_table" )


main_menu() {
    echo
    echo "========= 路由策略菜单 ========="
    echo "1) 查看所有规则并按编号删除"
    echo "2) 添加目标 IP 到接口"
    echo "3) 退出"
    echo "================================"
    read -rp "请输入你的选择: " main_choice

    case "$main_choice" in
        1) list_and_delete ;;
        2) add_by_interface ;;
        3) echo "已退出"; exit 0 ;;
        *) echo "无效选项"; main_menu ;;
    esac
}

list_and_delete() {
    echo
    echo "当前已有规则:"
    mapfile -t RULE_LINES < <(ip rule show | grep -E "lookup eth[01]_table")

    if [ ${#RULE_LINES[@]} -eq 0 ]; then
        echo "  （无）"
        main_menu
    fi

    for i in "${!RULE_LINES[@]}"; do
        line="${RULE_LINES[$i]}"
        table=$(echo "$line" | grep -o "eth[0-9]_table")
        ip=$(echo "$line" | awk '{for (i=1;i<=NF;i++) if ($i=="to") print $(i+1)}')
        printf "  %2d) %-15s [%s]\\n" $((i+1)) "$ip" "$table"
    done

    read -rp "请输入要删除的规则编号（空格分隔，直接回车跳过）: " nums
    for num in $nums; do
        idx=$((num-1))
        line="${RULE_LINES[$idx]}"
        ip=$(echo "$line" | awk '{for (i=1;i<=NF;i++) if ($i=="to") print $(i+1)}')
        table=$(echo "$line" | grep -o "eth[0-9]_table")
        if [ -n "$ip" ] && [ -n "$table" ]; then
            ip rule del to "$ip" table "$table"
            echo "Deleted: $ip from [$table]"
        else
            echo "Invalid number: $num"
        fi
    done

    save_persistent_rules
    main_menu
}

add_by_interface() {
    echo "选择要添加规则的接口:"
    echo "1) eth0 (10.7.1.27)"
    echo "2) eth1 (10.8.0.230)"
    read -rp "输入编号: " choice

    if [ "$choice" = "1" ]; then
        IFACE="eth0"
    elif [ "$choice" = "2" ]; then
        IFACE="eth1"
    else
        echo "无效选择"
        main_menu
    fi

    TABLE=${TABLES[$IFACE]}
    GW=${GWS[$IFACE]}
    NET=${NETS[$IFACE]}

    ip route add default via "$GW" dev "$IFACE" table "$TABLE" 2>/dev/null
    ip route add "$NET" dev "$IFACE" scope link table "$TABLE" 2>/dev/null

    read -rp "请输入要添加的目标 IP（空格分隔）: " new_ips
    for ip in $new_ips; do
        ip rule add to "$ip" table "$TABLE"
        echo "Added: $ip -> $TABLE"
    done

    save_persistent_rules
    main_menu
}

# 保存当前所有规则为持久化脚本
save_persistent_rules() {
    local persist_file="/usr/local/bin/route-policy-restore.sh"
    {
        echo "#!/bin/bash"
        echo "# Auto-generated restore script"
        echo
        echo "grep -q \"100 eth0_table\" /etc/iproute2/rt_tables || echo \"100 eth0_table\" >> /etc/iproute2/rt_tables"
        echo "grep -q \"200 eth1_table\" /etc/iproute2/rt_tables || echo \"200 eth1_table\" >> /etc/iproute2/rt_tables"
        echo
    } > "$persist_file"

    for iface in "${!TABLES[@]}"; do
        table="${TABLES[$iface]}"
        gw="${GWS[$iface]}"
        net="${NETS[$iface]}"

        echo "# $iface rules for table $table" >> "$persist_file"
        echo "ip route add default via $gw dev $iface table $table 2>/dev/null" >> "$persist_file"
        echo "ip route add $net dev $iface scope link table $table 2>/dev/null" >> "$persist_file"

        mapfile -t RULES < <(ip rule show | grep "lookup $table")
        for rule in "${RULES[@]}"; do
            ip_to=$(echo "$rule" | awk '{for (i=1;i<=NF;i++) if ($i=="to") print $(i+1)}')
            [[ -n "$ip_to" ]] && echo "ip rule add to $ip_to table $table" >> "$persist_file"
        done
        echo >> "$persist_file"
    done

    chmod +x "$persist_file"
    echo "[✔] 已保存规则到 $persist_file"
}

install_systemd_service() {
    local service_file="/etc/systemd/system/route-policy-restore.service"
    local script_file="/usr/local/bin/route-policy-restore.sh"

    # 如果服务文件不存在则创建
    if [ ! -f "$service_file" ]; then
        echo "[+] 正在创建 systemd 服务：$service_file"

        tee "$service_file" > /dev/null <<EOF
[Unit]
Description=Restore IP routing policy rules
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=$script_file
RemainAfterExit=true

[Install]
WantedBy=multi-user.target
EOF

        systemctl daemon-reload
        systemctl enable --now route-policy-restore.service

        echo "[✔] 服务已创建并启用：route-policy-restore"
    fi
}

main_menu
