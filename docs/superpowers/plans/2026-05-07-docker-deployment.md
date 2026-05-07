# Docker 部署 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 将 acemcp-relay 容器化，并通过 docker-compose 一键部署 relay + PostgreSQL + Redis。

**Architecture:** 多阶段 Dockerfile（golang:1.25-alpine 编译，distroless/static 运行），docker-compose 管理三个服务，relay 依赖 postgres/redis 健康检查后启动。日志只输出 stdout，敏感配置通过 .env 注入。

**Tech Stack:** Go 1.25, Gin, PostgreSQL 15, Redis 7, Docker multi-stage build, distroless/static-debian12

---

### Task 1: 修改 main.go — 日志改为 stdout only

**Files:**
- Modify: `main.go:1244-1251`

- [ ] **Step 1: 修改日志初始化代码**

在 `main.go` 的 `main()` 函数中，找到以下代码块（约第 1244 行）：

```go
// 设置日志同时输出到控制台和文件
logFile, err := os.OpenFile("gin.log", os.O_CREATE|os.O_WRONLY|os.O_APPEND, 0644)
if err != nil {
    panic("无法创建日志文件: " + err.Error())
}
gin.DefaultWriter = io.MultiWriter(os.Stdout, logFile)
gin.DefaultErrorWriter = io.MultiWriter(os.Stderr, logFile)
log.SetOutput(io.MultiWriter(os.Stdout, logFile))
```

替换为：

```go
// 日志只输出到 stdout/stderr（容器环境，由 Docker logging driver 收集）
gin.DefaultWriter = os.Stdout
gin.DefaultErrorWriter = os.Stderr
log.SetOutput(os.Stdout)
```

- [ ] **Step 2: 移除 os.OpenFile 相关的 import（如果 os 包其他地方还在用则保留）**

检查 `os` 包是否还有其他使用（`os.Getenv`、`os.Stderr` 等），确认保留 `"os"` import。
移除不再使用的变量 `logFile` 和相关的 `err` 变量引用即可。

- [ ] **Step 3: 构建验证**

```bash
go build .
```

预期：编译成功，无报错。

- [ ] **Step 4: Commit**

```bash
git add main.go
git commit -m "feat: redirect logs to stdout only for container environment"
```

---

### Task 2: 修改 main.go — 支持 REDIS_HOST 环境变量

**Files:**
- Modify: `main.go`（变量声明区、loadConfig、initRedis 三处）

- [ ] **Step 1: 在变量声明区新增 redisHost**

找到（约第 36 行）：
```go
var (
    serverAddr      string
    augmentAPIURL   string
    augmentAPIToken string
    dbHost          string
    dbPort          int
    dbUser          string
    dbPassword      string
    dbName          string
    redisPort       int
    apiKeyCacheTTL  time.Duration
    sessionTTL      time.Duration
)
```

替换为：
```go
var (
    serverAddr      string
    augmentAPIURL   string
    augmentAPIToken string
    dbHost          string
    dbPort          int
    dbUser          string
    dbPassword      string
    dbName          string
    redisHost       string
    redisPort       int
    apiKeyCacheTTL  time.Duration
    sessionTTL      time.Duration
)
```

- [ ] **Step 2: 在 loadConfig() 中新增 redisHost 赋值**

找到（约第 277 行）：
```go
redisPort = getEnvInt("REDIS_PORT", 6379)
```

在其上方新增一行：
```go
redisHost = getEnv("REDIS_HOST", "localhost")
redisPort = getEnvInt("REDIS_PORT", 6379)
```

- [ ] **Step 3: 修改 initRedis() 使用 redisHost**

找到（约第 414 行）：
```go
redisClient = redis.NewClient(&redis.Options{
    Addr: fmt.Sprintf("localhost:%d", redisPort),
    DB:   0,
})
```

替换为：
```go
redisClient = redis.NewClient(&redis.Options{
    Addr: fmt.Sprintf("%s:%d", redisHost, redisPort),
    DB:   0,
})
```

- [ ] **Step 4: 构建验证**

```bash
go build .
```

预期：编译成功，无报错。

- [ ] **Step 5: Commit**

```bash
git add main.go
git commit -m "feat: support REDIS_HOST env var for container deployment"
```

---

### Task 3: 更新 .env.example

**Files:**
- Modify: `.env.example`

- [ ] **Step 1: 更新 .env.example 内容**

将 `.env.example` 替换为以下内容：

```
# Server Configuration
# 容器环境需监听 0.0.0.0，裸机部署可用 127.0.0.1:3009
SERVER_ADDR=0.0.0.0:3009

# Augment API Configuration
AUGMENT_API_URL=https://your-api-url.com
AUGMENT_API_TOKEN=your-api-token-here

# PostgreSQL Database Configuration
# docker-compose 部署时 DB_HOST 填写 service 名称 "postgres"
DB_HOST=postgres
DB_PORT=5432
DB_USER=postgres
DB_PASSWORD=your-password-here
DB_NAME=acemcp

# PostgreSQL docker-compose 服务配置（需与上方保持一致）
POSTGRES_USER=postgres
POSTGRES_PASSWORD=your-password-here
POSTGRES_DB=acemcp

# Redis Configuration
# docker-compose 部署时 REDIS_HOST 填写 service 名称 "redis"
REDIS_HOST=redis
REDIS_PORT=6379
API_KEY_CACHE_TTL=1h

# Session Configuration
SESSION_TTL=5m
```

- [ ] **Step 2: 确认 .env 在 .gitignore 中**

```bash
grep -n "\.env" .gitignore
```

预期：`.env` 已在 `.gitignore` 中（如果不存在则添加 `.env` 一行）。

- [ ] **Step 3: Commit**

```bash
git add .env.example
git commit -m "chore: update .env.example for docker-compose deployment"
```

---

### Task 4: 创建 .dockerignore

**Files:**
- Create: `.dockerignore`

- [ ] **Step 1: 创建 .dockerignore**

```
.git
.env
*.log
gin.log
docs/
README.md
docker-compose.yml
.dockerignore
```

- [ ] **Step 2: Commit**

```bash
git add .dockerignore
git commit -m "chore: add .dockerignore"
```

---

### Task 5: 创建 Dockerfile

**Files:**
- Create: `Dockerfile`

- [ ] **Step 1: 创建 Dockerfile**

```dockerfile
# ── Stage 1: Build ──────────────────────────────────────────────────────────
FROM golang:1.25-alpine AS builder

# 安装构建依赖（CGO 禁用，alpine 下无需 gcc）
RUN apk add --no-cache git

WORKDIR /build

# 先复制依赖文件，利用 Docker layer 缓存
COPY go.mod go.sum ./
RUN go mod download

# 复制源码并编译
COPY *.go ./
RUN CGO_ENABLED=0 GOOS=linux GOARCH=amd64 \
    go build -ldflags="-w -s" -o acemcp-relay .

# ── Stage 2: Run ─────────────────────────────────────────────────────────────
FROM gcr.io/distroless/static-debian12:nonroot

WORKDIR /app

# 从 builder 复制二进制
COPY --from=builder /build/acemcp-relay .

# 使用非 root 用户（distroless nonroot 镜像默认 uid=65532）
USER nonroot:nonroot

EXPOSE 3009

ENTRYPOINT ["/app/acemcp-relay"]
```

- [ ] **Step 2: 本地构建测试**

```bash
docker build -t acemcp-relay:local .
```

预期：构建成功，最终输出类似：
```
Successfully built xxxxxxxx
Successfully tagged acemcp-relay:local
```

- [ ] **Step 3: 验证镜像大小**

```bash
docker images acemcp-relay:local
```

预期：SIZE 在 20MB 以内。

- [ ] **Step 4: Commit**

```bash
git add Dockerfile
git commit -m "feat: add multi-stage Dockerfile with distroless runtime"
```

---

### Task 6: 创建 docker-compose.yml

**Files:**
- Create: `docker-compose.yml`

- [ ] **Step 1: 创建 docker-compose.yml**

```yaml
services:
  relay:
    build: .
    image: acemcp-relay:latest
    ports:
      - "3009:3009"
    env_file:
      - .env
    depends_on:
      postgres:
        condition: service_healthy
      redis:
        condition: service_healthy
    restart: unless-stopped

  postgres:
    image: postgres:15-alpine
    env_file:
      - .env
    volumes:
      - postgres_data:/var/lib/postgresql/data
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U $${POSTGRES_USER} -d $${POSTGRES_DB}"]
      interval: 5s
      timeout: 5s
      retries: 10
    restart: unless-stopped

  redis:
    image: redis:7-alpine
    healthcheck:
      test: ["CMD", "redis-cli", "ping"]
      interval: 5s
      timeout: 3s
      retries: 10
    restart: unless-stopped

volumes:
  postgres_data:
```

- [ ] **Step 2: 复制 .env.example 为 .env 并填写真实配置**

```bash
cp .env.example .env
# 编辑 .env，填写真实的 AUGMENT_API_URL、AUGMENT_API_TOKEN、DB_PASSWORD 等
```

- [ ] **Step 3: 验证 docker-compose 配置**

```bash
docker compose config
```

预期：输出合并后的配置，无报错。

- [ ] **Step 4: 启动服务**

```bash
docker compose up -d
```

预期：三个服务依次启动，relay 等待 postgres 和 redis 健康检查通过后启动。

- [ ] **Step 5: 验证服务状态**

```bash
docker compose ps
```

预期：三个服务均为 `running` 状态，relay 的 health 显示正常。

- [ ] **Step 6: 验证 relay 日志**

```bash
docker compose logs relay
```

预期：看到 Gin 启动日志，无 panic 或 fatal 错误。

- [ ] **Step 7: 验证端口连通性**

```bash
curl -s -o /dev/null -w "%{http_code}" http://localhost:3009/get-models \
  -H "Authorization: Bearer invalid-token"
```

预期：返回 `401`（说明服务正常响应，认证中间件生效）。

- [ ] **Step 8: Commit**

```bash
git add docker-compose.yml
git commit -m "feat: add docker-compose for full-stack deployment"
```

---

### Task 7: 更新 README.md — 新增 Docker 部署章节

**Files:**
- Modify: `README.md`

- [ ] **Step 1: 在 README.md 末尾新增 Docker 部署章节**

在 `## 日志` 章节之后追加：

```markdown
## Docker 部署

### 前置要求

- Docker 20.10+
- Docker Compose v2

### 快速部署

1. 复制并编辑环境变量文件：

```bash
cp .env.example .env
# 编辑 .env，填写 AUGMENT_API_URL、AUGMENT_API_TOKEN、DB_PASSWORD 等必填项
```

2. 启动全部服务：

```bash
docker compose up -d
```

3. 查看服务状态：

```bash
docker compose ps
docker compose logs relay
```

4. 停止服务：

```bash
docker compose down
```

### 数据持久化

PostgreSQL 数据存储在 Docker named volume `postgres_data` 中，`docker compose down` 不会删除数据。
如需清除数据：

```bash
docker compose down -v
```

### 镜像说明

- 使用多阶段构建，最终镜像基于 `gcr.io/distroless/static-debian12`
- 镜像体积约 15-20MB，以非 root 用户运行
- 日志输出到 stdout，由 Docker logging driver（默认 json-file）收集
```

- [ ] **Step 2: Commit**

```bash
git add README.md
git commit -m "docs: add docker deployment section to README"
```
