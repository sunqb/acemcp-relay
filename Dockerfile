# ── Stage 1: Build ──────────────────────────────────────────────────────────
FROM golang:1.25-alpine AS builder

# 安装构建依赖
RUN apk add --no-cache git

WORKDIR /build

# 设置 Go 代理（国内加速）
ENV GOPROXY=https://goproxy.cn,direct

# 先复制依赖文件，利用 Docker layer 缓存
COPY go.mod go.sum ./
RUN go mod download

# 复制源码并编译
COPY *.go ./
RUN CGO_ENABLED=0 \
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
