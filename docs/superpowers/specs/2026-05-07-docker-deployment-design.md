# Docker 部署设计文档

**日期**：2026-05-07  
**状态**：待实施

## 背景

acemcp-relay 是一个 Go HTTP 反向代理服务，依赖 PostgreSQL 和 Redis。目标是将其容器化，并通过 docker-compose 一键部署全部服务。

## 决策

| 项目 | 决策 |
|------|------|
| Dockerfile 策略 | 多阶段构建 + distroless/static 最终镜像 |
| 依赖部署方式 | PostgreSQL + Redis 一并纳入 docker-compose |
| 日志策略 | 只输出到 stdout/stderr，不写本地文件 |
| 配置注入 | 通过 `.env` 文件注入，不写死在 compose 文件里 |

## 需要的代码改动

### 1. main.go：日志改为 stdout only

删除 `gin.log` 文件写入，将所有 writer 改为直接写 stdout/stderr：

```go
// 改前
logFile, _ := os.OpenFile("gin.log", ...)
gin.DefaultWriter = io.MultiWriter(os.Stdout, logFile)
gin.DefaultErrorWriter = io.MultiWriter(os.Stderr, logFile)
log.SetOutput(io.MultiWriter(os.Stdout, logFile))

// 改后
gin.DefaultWriter = os.Stdout
gin.DefaultErrorWriter = os.Stderr
log.SetOutput(os.Stdout)
```

### 2. main.go：Redis 支持 REDIS_HOST 环境变量

当前代码 Redis 地址硬编码为 `localhost`，容器内不可达，需新增 `REDIS_HOST` 配置：

```go
// 新增变量
redisHost string

// loadConfig 中新增
redisHost = getEnv("REDIS_HOST", "localhost")

// initRedis 中修改
Addr: fmt.Sprintf("%s:%d", redisHost, redisPort),
```

### 3. .env.example：新增 REDIS_HOST

```
REDIS_HOST=redis
```

### 4. SERVER_ADDR 默认值

容器内需监听 `0.0.0.0`，通过 `.env` 配置 `SERVER_ADDR=0.0.0.0:3009`，代码默认值保持不变。

## 新增文件

### Dockerfile

```
多阶段构建：
  Stage 1 (builder): golang:1.25-alpine
    - 设置 CGO_ENABLED=0 GOOS=linux
    - go mod download
    - go build -o acemcp-relay .
  Stage 2 (final): gcr.io/distroless/static-debian12
    - 从 builder 复制二进制
    - 以非 root 用户运行（nonroot:nonroot）
    - EXPOSE 3009
    - ENTRYPOINT ["/acemcp-relay"]
```

### docker-compose.yml

```
services:
  relay:
    build: .
    ports: ["3009:3009"]
    env_file: .env
    depends_on:
      postgres: { condition: service_healthy }
      redis:    { condition: service_healthy }
    restart: unless-stopped

  postgres:
    image: postgres:15-alpine
    env_file: .env  # POSTGRES_USER / POSTGRES_PASSWORD / POSTGRES_DB
    volumes: [postgres_data:/var/lib/postgresql/data]
    healthcheck: pg_isready -U ${DB_USER}
    restart: unless-stopped

  redis:
    image: redis:7-alpine
    healthcheck: redis-cli ping
    restart: unless-stopped

volumes:
  postgres_data:
```

### .env 配置对应关系

| docker-compose 变量 | relay 变量 | 说明 |
|---------------------|------------|------|
| POSTGRES_USER | DB_USER | 需保持一致 |
| POSTGRES_PASSWORD | DB_PASSWORD | 需保持一致 |
| POSTGRES_DB | DB_NAME | 需保持一致 |
| — | DB_HOST=postgres | 固定为 compose service 名 |
| — | REDIS_HOST=redis | 固定为 compose service 名 |
| — | SERVER_ADDR=0.0.0.0:3009 | 容器内监听全部接口 |

## 数据持久化

- PostgreSQL 数据通过 named volume `postgres_data` 持久化到宿主机
- Redis 不做持久化（仅缓存，重启后 API Key 缓存会重建）
- 日志由 Docker logging driver 管理（默认 json-file）

## 安全注意事项

- `.env` 文件包含敏感信息，已在 `.gitignore` 中排除
- distroless 镜像无 shell，攻击面最小
- relay 以 nonroot 用户运行
- postgres 和 redis 不对外暴露端口（仅 relay 暴露 3009）
