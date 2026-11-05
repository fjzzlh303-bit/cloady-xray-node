# 多阶段 Dockerfile：官方 Xray 镜像没有 shell，只把它当二进制来源，
# 把二进制拷进 Alpine 运行。Cloady 边缘负责 TLS，容器内只跑明文 WS。
# 构建与运行都不含任何密钥；UUID 与路径走部署时的环境变量。

# Stage 1：官方镜像，仅取二进制
FROM ghcr.io/xtls/xray-core:latest AS xray

# Stage 2：Alpine 运行时
FROM alpine:3.21
RUN apk add --no-cache ca-certificates
COPY --from=xray /usr/local/bin/xray /usr/local/bin/xray
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh
EXPOSE 3000
ENTRYPOINT ["/entrypoint.sh"]
