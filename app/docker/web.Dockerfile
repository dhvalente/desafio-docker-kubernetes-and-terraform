# Build de contexto: raiz do repositório (docker build -f app/docker/web.Dockerfile .)
#
# Front 100% estático (sem build step, ver app/web/app.js). O nginx oficial
# processa automaticamente arquivos em /etc/nginx/templates/*.template com
# envsubst no boot, substituindo ${API_UPSTREAM} pelo valor da env — por isso
# a MESMA imagem serve no docker-compose (API_UPSTREAM=api:8080) e no
# Kubernetes (API_UPSTREAM=<service-da-api>:80) sem rebuild.

FROM nginx:1.27-alpine

COPY app/web/nginx.conf.template /etc/nginx/templates/default.conf.template
COPY app/web/index.html app/web/app.js app/web/styles.css /usr/share/nginx/html/

# Default de conveniência para rodar a imagem isolada; em qualquer ambiente
# real (compose ou Helm) o valor correto é injetado via env no runtime.
ENV API_UPSTREAM=api:8080

EXPOSE 8080
