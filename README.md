主要适用于双网卡，执行后

root@debian-11-change:~# bash route.sh 

========= 路由策略菜单 =========
1) 查看所有规则并按编号删除
2) 添加目标 IP 到接口
3) 退出
================================

请输入你的选择: 

注意：里面的网卡及IP等需根据自己情况提前修改后再执行

```
apt install -y jq
wget https://raw.githubusercontent.com/wiznb/route/refs/heads/main/route.sh && chmod +x route.sh
```
执行
```
bash route.sh
```
