# 前端镜像：托管 Flutter Web 构建产物，并把 /api 反向代理到后端容器
FROM nginx:1.27-alpine

COPY nginx.conf /etc/nginx/conf.d/default.conf
COPY build/web /usr/share/nginx/html

EXPOSE 80
