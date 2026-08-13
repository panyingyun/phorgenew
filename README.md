# Phorge Docker 镜像（中文汉化版）

非官方 Phorge Docker 镜像，内置简体中文语言包，apk/pip 使用华为云源。衍生自 [rrvenn/phorge](https://github.com/rrvenn/phorge)。

## 编译

需 Docker ≥ 20.10。构建时从 GitHub 拉取源码；若有本地代理（如 Clash 监听 `127.0.0.1:7890`）：

```bash
docker build --network host -t phorge-zh:latest .
```

`--network host` 必填，否则容器内访问不到宿主机代理。

无代理时，把源码放到 `phorge-src/`，按 Dockerfile 注释把 `git clone` 换成 `COPY`，再执行：

```bash
docker build -t phorge-zh:latest .
```

代理地址改 `configs/gitconfig`；镜像名改完后同步改 `docker-compose.yml` 里 `ph-web` 的 `image`。

## 部署

1. 按需编辑同目录 `.env`（至少改 `PHORGE_BASE_URI`、数据库密码、S3 密钥）。
2. 启动：

```bash
docker compose up -d
```

3. 本机 `/etc/hosts` 加 `127.0.0.1 phorge.local`，访问 `http://phorge.local/`。RustFS 控制台：`http://<IP>:9001`。

### 首次使用

1. 启用用户名/密码登录（或在 Config → Auth 添加 Provider）：

```bash
docker compose exec ph-web sh -c \
  'mariadb -h ph-database -u phorge_user -pstrongpassword --skip-ssl phabricator_auth \
   -e "INSERT INTO auth_providerconfig (phid, providerClass, providerType, providerDomain, isEnabled, shouldAllowLogin, shouldAllowRegistration, shouldAllowLink, shouldAllowUnlink, shouldTrustEmails, properties, dateCreated, dateModified) VALUES (\"PHID-AUTH-$(head -c 20 /dev/urandom | xxd -p -c 40)\", \"PhabricatorPasswordAuthProvider\", \"password\", \"self\", 1, 1, 1, 1, 1, 1, \"[]\", UNIX_TIMESTAMP(), UNIX_TIMESTAMP());"'
```

2. 访问 `/auth/register/` 注册；管理员批准：

```bash
docker compose exec ph-web sh -c 'cd /var/www/phorge/phorge && bin/user approve --user <用户名>'
```

3. 设置 → 翻译，选「中文（简体中文）」。

### 常用命令

```bash
docker compose logs -f ph-web
docker compose restart
docker compose down          # 保留数据
docker compose down -v       # 清空数据卷
docker compose exec ph-web sh -c 'cd /var/www/phorge/phorge && bin/storage upgrade --force'
```

## Git LFS

镜像已启用 `diffusion.allow-git-lfs`。仅对 Diffusion 中托管（hosted）的 Git 仓库有效：

```bash
git clone http://phorge.local/diffusion/<CALLSIGN>/<repo>.git
cd <repo>
git lfs install
git lfs track "*.bin"   # 按需改模式
git add .gitattributes <大文件>
git commit -m "track lfs files"
git push
```

## 上游

- [phorgeit/phorge](https://github.com/phorgeit/phorge)
- [phorgeit/arcanist](https://github.com/phorgeit/arcanist)
