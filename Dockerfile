FROM registry:latest
LABEL maintainer="ZhangSean <zxf2342@qq.com>"
ENV PROXY_REMOTE_URL="" \
    DELETE_ENABLED=""
COPY entrypoint.sh /entrypoint.sh
