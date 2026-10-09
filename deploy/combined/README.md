# 与 codex-proxy-rs 联合部署

状态：当前。已在 Linux/amd64 临时环境验证 Compose、两个应用启动、HTTP 检查、数据库账号隔离、PG/Redis 重启和 PG 逻辑备份；未验证真实上游账号调用和 ARM64 构建。

适用于 Linux 服务器上的全新部署，需要 Docker Engine、Compose 插件和 OpenSSL。所有命令均从本目录 `deploy/combined/` 执行。无需下载另一份 codex-proxy-rs 仓库，也不要同时启动两个项目原来的 Compose。

| 服务 | 用途 | 宿主机端口 |
| --- | --- | --- |
| PostgreSQL 18 | 两个独立数据库 `codex_proxy`、`chatgpt2api`，分别由同名非超级用户持有 | 不发布 |
| Redis 8 | codex-proxy-rs 协调状态，启用密码和 AOF | 不发布 |
| codex-proxy-rs | `ghcr.io/const-time/codex-proxy-rs` | `127.0.0.1:8080` |
| chatgpt2api | `ghcr.io/const-time/chatgpt2api` | `127.0.0.1:3000` |

两个应用共用 Docker 网络和 PG 实例，各自管理数据库表、升级和文件数据。应用账号不能连接对方的数据库。Redis 只供 codex-proxy-rs 使用。

## 1. 准备配置

在本仓库根目录进入本目录，只在首次部署时复制：

```bash
cd deploy/combined
umask 077
cp .env.example .env
cp config.example.yaml config.yaml
printf '{}\n' > config.json
```

分别执行六次 `openssl rand -hex 24`，将不同结果填入以下位置，不要复用密码：

| 文件 | 字段 | 用途 |
| --- | --- | --- |
| `.env` | `POSTGRES_ADMIN_PASSWORD` | PG 初始化管理员密码 |
| `.env` | `CHATGPT2API_DATABASE_PASSWORD` | chatgpt2api 专用数据库密码 |
| `.env` | `CHATGPT2API_AUTH_KEY` | chatgpt2api 控制台登录及 API 密钥 |
| `config.yaml` | `store.database.password` | codex-proxy-rs 专用数据库密码，保留 `&postgres_password` 锚点 |
| `config.yaml` | `store.redis.password` | Redis 密码，保留 `&redis_password` 锚点 |
| `config.yaml` | `admin.default_password` | codex-proxy-rs 首次管理员密码 |

`config.yaml` 沿用 codex-proxy-rs 配置格式，凭据通过 YAML 锚点提供给数据库初始化和 Redis。不要将 codex-proxy-rs 密码写进其 URL，也不要删除底部的 `services` 桥接区。`.env` 由 Compose 读取，不会替换 `config.yaml` 中的内容。

设置配置文件权限，使 codex-proxy-rs 容器的 `10001` 组可以读取：

```bash
sudo chown "$(id -u):10001" config.yaml
chmod 0640 config.yaml
chmod 0600 .env config.json
docker compose config --quiet
```

业务数据使用独立命名卷，无需手动创建数据目录。不要把含真实凭据的 `.env`、`config.yaml`、`config.json` 提交到 Git。

## 2. 启动

两个应用镜像均已发布且可以拉取时：

```bash
docker compose pull
docker compose up -d --wait
docker compose ps
```

**如果 chatgpt2api 的 GHCR 镜像尚未发布或无法拉取**，保留本仓库源码，使用提供的本地构建 overlay：

```bash
docker compose -f compose.yaml -f compose.build.yaml build chatgpt2api
docker compose -f compose.yaml -f compose.build.yaml up -d --wait
docker compose -f compose.yaml -f compose.build.yaml ps
```

本地构建只替换 chatgpt2api 镜像，codex-proxy-rs 仍拉取自己的 GHCR 镜像。以后更新源码并重新执行上述构建、启动命令。镜像部署可在 `.env` 将两个 `IMAGE` 固定到各自已发布的版本，版本号不必相同。

`--wait` 检查 PG、Redis 和 codex-proxy-rs 的健康状态；chatgpt2api 未定义容器健康检查，需要另行检查 HTTP：

```bash
curl -fsS http://127.0.0.1:8080/healthz
curl -fsS -o /dev/null http://127.0.0.1:3000/
docker compose logs --tail 100 codex-proxy-rs chatgpt2api
```

codex-proxy-rs 登录账号默认是 `admin@cpr.local`，密码是 `config.yaml` 的 `admin.default_password`；chatgpt2api 使用 `.env` 中的 `CHATGPT2API_AUTH_KEY`。

默认仅允许宿主机访问，适合宿主机 HTTPS 反向代理。若直接从局域网访问，在 `.env` 中将 `BIND_ADDRESS` 改为服务器局域网 IP，然后重新创建应用容器。两个应用使用不同端口或域名；反向代理需保留 Authorization、Origin 和 WebSocket Upgrade，并关闭 SSE 缓冲。应用间访问可用 `http://codex-proxy-rs:8080` 和 `http://chatgpt2api:80`，不要在容器内用 localhost 指向另一个应用。

## 3. 数据与维护

默认 Compose 项目名为 `ai-services`，持久化卷包括：

- `postgres-data`：两个数据库的物理数据，由一个 PG 容器持有。
- `redis-data`：Redis AOF。
- `cpr-data`、`cpr-logs`：codex-proxy-rs 运行数据及日志。
- `chatgpt2api-data`：图片、任务等文件数据。
- `chatgpt2api-runtime`：可更新的应用运行目录，不替代业务数据备份。

实际卷名带项目名前缀，例如 `ai-services_postgres-data`。首次 PG 初始化脚本只在空卷上运行；不要通过修改 `.env` 或 `config.yaml` 来重置已初始化的数据库密码，也不要为重跑初始化删除已有卷。

数据库逻辑备份使用 PG 18 容器内的客户端，分别导出：

```bash
mkdir -p backups
chmod 0700 backups
umask 077
docker compose exec -T postgres sh -c 'PGPASSWORD="$POSTGRES_PASSWORD" pg_dump -U postgres -d codex_proxy --format=custom --no-owner --no-privileges' > "backups/codex_proxy-$(date +%Y%m%d-%H%M%S).dump"
docker compose exec -T postgres sh -c 'PGPASSWORD="$POSTGRES_PASSWORD" pg_dump -U postgres -d chatgpt2api --format=custom --no-owner --no-privileges' > "backups/chatgpt2api-$(date +%Y%m%d-%H%M%S).dump"
```

文件数据和配置需要另行备份；如需让数据库备份与文件数据保持一致，先停止两个应用，保留 PG 运行，完成备份后再启动。PG 重启会同时影响两个应用。

镜像部署更新应用：

```bash
docker compose pull codex-proxy-rs chatgpt2api
docker compose up -d --wait codex-proxy-rs chatgpt2api
```

`docker compose down` 保留命名卷；日常维护不要使用 `down -v`。原始 `docker compose config` 输出包含密码，验证使用 `config --quiet`。
