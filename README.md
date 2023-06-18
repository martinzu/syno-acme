# syno-acme

通过acme协议更新群晖HTTPS泛域名证书的自动脚本

本脚本 fork 自 [andyzhshg/syno-acme](https://github.com/andyzhshg/syno-acme)，在它的基础上
- 将下载工具和更新证书分开
- 支持自动下载最新版本的 acme.sh ，不再依赖 syno-acme 本身来更新
- 自动提示输入 sudo 密码
- python 部分支持 python3
- 支持syncthing

注释掉重启 webservice 部分，因为不通用，建议有能力者自行写这部分代码。

## 安装

```bash
# 1. 将脚本复制到 home 文件夹下
cd ~
git clone git@github.com:goosy/syno-acme.git

# 2. 更新 acme.sh 工具
syno-acme/cert-up.sh install

# 3. 修改 ~/.acme.sh/config 文件
# 填写你的电子邮箱、域名、域名服务商、是否也更新 syncthing 证书等等
vim ~/.acme.sh/config

# 4. 注册电子邮箱，仅第一次需要。
syno-acme/cert-up.sh register

# 5. 更新证书及服务
syno-acme/cert-up.sh update

# 6. 根据需要回退证书（第4步出错时也会自动调用）
syno-acme/cert-up.sh revert
```

## 维护

仅第一次需要从头执行到第5步，以后只需要第2步和第5步。

第2步的作用仅仅是更新acme.sh工具，可在网络好的时候手动进行，特别是中国的网络有时候……
不做第2步大部分情况下也不影响更新证书，建议仅在acme.sh工具有新版时更新，以保证与CA站点的兼容性。

第5步是更新证书，建议把第4步的脚本放入 synology NAS 的定期任务中，周期可设为3个月。
