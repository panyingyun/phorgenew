# Phorge Docker 镜像(中文汉化版)

本仓库提供 **Phorge** 的非官方 Docker 镜像,针对国内环境做了定制:

- **简体中文语言包**:内置约 2000 条高频界面字符串的中文翻译(导航、按钮、菜单、设置、任务/代码库/评审等核心应用界面)。
- **华为云镜像源**:`apk`(Alpine 的软件包管理器,相当于 apt)与 `pip` 均切换到华为云镜像,加速构建。
- **持久化 git 代理**:构建时通过代理从 GitHub 下载 Phorge 源码,代理配置固化进镜像(`/etc/gitconfig` + `git config --global`),重启/重建不丢失。
- **兼容性修复**:修复了上游 Dockerfile 在 Alpine 3.24 下 `ldb-dev` 无法安装的问题。

> 注意:本镜像为个人定制版,与上游 Phorge 项目无隶属关系。

---

## 0、前置条件

| 依赖 | 说明 |
|---|---|
| Docker | 版本 ≥ 20.10,建议开启 BuildKit(默认开启);包含 `docker compose` 插件(v2) |
| 本地代理(可选但推荐) | 构建时需要从 GitHub 拉取 `phorgeit/phorge` 与 `phorgeit/arcanist` 源码。若宿主机有代理(如 Clash),请监听在 `127.0.0.1:7890`;没有代理时使用离线源码方案(见 1.4 节) |
| 磁盘空间 | 构建过程约需 2~3 GB(源码 + PHP 扩展编译产物) |

---

## 1、如何编译

### 1.1 标准编译(推荐)

```bash
# 在仓库根目录执行
docker build --network host -t phorge-zh:latest .
```

- `--network host` **必填**:构建容器内 `127.0.0.1:7890` 需要指向宿主机的代理,默认 bridge 网络下该地址指向容器自身、代理不可达。
- 构建过程:
  1. `apk` 从华为云 Alpine 镜像安装运行时与编译依赖;
  2. 通过代理 `git clone` 下载 `phorgeit/arcanist` 与 `phorgeit/phorge` 源码;
  3. 编译 PHP 扩展(APCu、gd、ldap 等),配置 pip 华为云 PyPI 源;
  4. 将 `extensions/` 下的中文语言包复制进 Phorge 的 `src/extensions/`。

### 1.2 常见问题

| 现象 | 解决 |
|---|---|
| `~/.docker` 只读(sandbox 环境) | 加 `DOCKER_CONFIG=/tmp/docker-config`:`DOCKER_CONFIG=/tmp/docker-config docker build --network host -t phorge-zh:latest .` |
| 代理未启动,git clone 超时 | 先启动代理再构建;或改用离线源码方案(见 1.4) |
| `apk add` 报 `ldb-dev` 相关错误 | 已在本仓库修复(移除 `ldb-dev`,PHP ldap 仅需 `openldap-dev`),如仍出现请确认基于最新 Dockerfile |
| 构建很慢 | 首次构建需下载依赖与源码;华为云源已加速软件包,源码走代理下载 |

### 1.3 自定义编译

- 修改 `configs/gitconfig` 可调整持久化 git 代理地址(默认 `http://127.0.0.1:7890` / `https://127.0.0.1:7890`)。
- 修改 `Dockerfile` 中的 `git clone` 行可更换源码仓库地址。
- 更换镜像 tag:`docker build --network host -t <你的镜像名>:<tag> .`,并同步修改 `docker-compose.yml` 中 `ph-web` 的 `image` 字段。

### 1.4 离线编译(无代理)

没有代理时,可把源码预先放入 `phorge-src/` 目录,并将 Dockerfile 中的 `git clone` 步骤替换为 `COPY`(Dockerfile 注释里有说明):

```bash
# 1. 从一台能访问 GitHub 的机器导出源码
docker exec <运行中的容器> sh -c 'cd /var/www/phorge && tar --exclude=".git" -czf /tmp/src.tgz phorge arcanist'
docker cp <运行中的容器>:/tmp/src.tgz .
mkdir -p phorge-src && tar xzf src.tgz -C phorge-src/
# 2. 编辑 Dockerfile:把 git clone 的 RUN 替换为
#    COPY ./phorge-src/phorge/ /var/www/phorge/phorge/
#    COPY ./phorge-src/arcanist/ /var/www/phorge/arcanist/
# 3. 构建(无需 --network host)
docker build -t phorge-zh:latest .
```

---

## 2、如何部署

### 2.1 准备 `.env`

复制 `docker-compose.yml` 同目录的 `.env` 模板并按需修改关键项:

```env
# 必填:对外访问的基础 URI(不含协议与末尾斜杠)
PHORGE_BASE_URI="phorge.local"

# 数据库(与 docker-compose.yml 中 mariadb 服务对应)
PHORGE_MYSQL_HOST="ph-database"
PHORGE_MYSQL_PORT="3306"
PHORGE_MYSQL_USER="phorge_user"
PHORGE_MYSQL_PASS="strongpassword"
PHORGE_MYSQL_DATABASE="phabricator_config"

# S3 存储(RustFS,compose 已包含 ph-storage 服务;兼容 MinIO)
PHORGE_STORAGE_ENGINE=s3
PHORGE_STORAGE_S3_SERVER=ph-storage
PHORGE_STORAGE_S3_PORT=9000
PHORGE_STORAGE_S3_SERVER_ACCESS_KEY=minio123sdfasdfas
PHORGE_STORAGE_S3_SERVER_SECRET_KEY=minioasdfasdf
PHORGE_STORAGE_S3_REGION="us-west-1"

# 时区
PHORGE_TIMEZONE="Asia/Shanghai"
```

完整变量说明见 `.env` 模板与 `scripts/startup.sh`。

### 2.2 启动

```bash
docker compose up -d          # 启动 ph-web + ph-database + ph-storage
docker compose ps             # 查看状态
docker compose logs -f ph-web # 查看日志
```

启动后访问:

- Phorge Web:`http://<PHORGE_BASE_URI>/`(本机需在 `/etc/hosts` 添加 `127.0.0.1 phorge.local`)
- RustFS 控制台:`http://<服务器IP>:9001`(S3 API 端口 9000)

### 2.3 首次使用(启用登录与中文)

1. **启用认证**:全新安装没有任何认证提供者,需先启用"用户名/密码"登录。可直接向数据库插入一条记录(在 `ph-web` 容器内执行):

   ```bash
   docker compose exec ph-web sh -c \
     'mariadb -h ph-database -u phorge_user -pstrongpassword --skip-ssl phabricator_auth \
      -e "INSERT INTO auth_providerconfig (phid, providerClass, providerType, providerDomain, isEnabled, shouldAllowLogin, shouldAllowRegistration, shouldAllowLink, shouldAllowUnlink, shouldTrustEmails, properties, dateCreated, dateModified) VALUES (\"PHID-AUTH-$(head -c 20 /dev/urandom | xxd -p -c 40)\", \"PhabricatorPasswordAuthProvider\", \"password\", \"self\", 1, 1, 1, 1, 1, 1, \"[]\", UNIX_TIMESTAMP(), UNIX_TIMESTAMP());"'
   ```

   或在 web 界面 Config → Auth 中添加 Provider。

2. **注册/登录**:访问 `http://phorge.local/auth/register/` 注册账户;新注册账户需管理员批准(`docker compose exec ph-web sh -c 'cd /var/www/phorge/phorge && bin/user approve --user <用户名>'`)。

3. **切换中文**:登录后进入 **设置 → 翻译 (Translation)**,选择 **中文 (简体中文)**。已用此语言包部署的实例可在数据库 `user_preferences` 表中为用户预设 `{"translation":"zh_CN"}`。

### 2.4 常用运维

```bash
docker compose restart      # 重启
docker compose down         # 停止(保留数据卷)
docker compose down -v      # 停止并删除数据卷(会清空数据库与文件,慎用)
docker compose exec ph-web sh -c 'cd /var/www/phorge/phorge && bin/storage upgrade --force'   # 升级数据库结构
```

### 2.5 Git LFS 使用

本镜像已启用 Git LFS:

- 镜像内置 `git-lfs` 客户端(Alpine 包,随镜像安装);
- 启动时自动设置 `diffusion.allow-git-lfs true`,Phorge 的 Git LFS 端点自动可用。

**前提**:使用 LFS 的仓库必须是 **hosted(托管)Git 仓库**(在 Phorge 的 Diffusion 中创建,而非导入的外部仓库)。

**本地使用步骤**:

```bash
# 1. 克隆 Phorge 中的 hosted Git 仓库
git clone http://phorge.local/diffusion/<CALLSIGN>/<repo>.git
cd <repo>

# 2. 初始化并跟踪大文件(一次性)
git lfs install
git lfs track "*.bin"            # 按需改为你的大文件模式,如 "*.zip" "*.iso"

# 3. 提交并推送
git add .gitattributes
git add <大文件>
git commit -m "track lfs files"
git push
```

推送后,大文件内容由 Phorge 通过 Git LFS 端点(`/diffusion/lfs/...`)存储,仓库本身只保存指针;克隆时 `git lfs pull`(或 `git clone` 时自动)拉取真实内容。

**注意事项**:

- 如提示 `Git LFS operation is not supported by this server`,确认配置已生效:`docker compose exec ph-web sh -c 'cd /var/www/phorge/phorge && bin/config get diffusion.allow-git-lfs'`;
- 大文件最终存储在对象存储(RustFS / S3)中,需保证其容量与带宽满足需求;
- 可用 `git lfs ls-files` 查看仓库中已跟踪的 LFS 文件。

---

## 3、仓库 fork 自

本仓库 fork/衍生自:

- **GitHub: [rrvenn/phorge](https://github.com/rrvenn/phorge)** — "Unofficial docker image of Phabricator app",非官方 Phorge Docker 镜像项目(镜像亦发布在 Docker Hub `rrvenn/phorge`)。

在此基础之上,本仓库做了以下定制:

1. **中文汉化**:新增 `extensions/` 语言包(约 2000 条 zh_CN 翻译),构建时自动装入 Phorge;
2. **国内源优化**:apk / pip 切换到华为云镜像;
3. **持久化 git 代理**:`configs/gitconfig` 与 Dockerfile 固化代理配置,构建可走代理拉取源码;
4. **兼容性修复**:适配 Alpine 3.24(移除 `ldb-dev`),`docker-compose.yml` 默认使用本地 `phorge-zh:latest` 镜像。

上游相关项目:

- Phorge 本体:[phorgeit/phorge](https://github.com/phorgeit/phorge)
- Arcanist:[phorgeit/arcanist](https://github.com/phorgeit/arcanist)

---

## 相关链接

- 本仓库 CI:`.github/workflows/dockerimage.yml`(监控上游 phorge 变化并构建镜像)
- 容器配置细节:`Dockerfile`、`scripts/startup.sh`、`docker-compose.yml`、`configs/`
