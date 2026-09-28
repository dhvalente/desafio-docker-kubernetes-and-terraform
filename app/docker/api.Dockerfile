# Build de contexto: raiz do repositório (docker build -f app/docker/api.Dockerfile .)
#
# Multi-stage: a etapa "build" tem toda a toolchain Go (~800MB+); a imagem final
# carrega só o binário estático, numa base distroless sem shell, sem package
# manager e sem libc dinâmica — menor superfície de ataque e pull bem mais rápido.

FROM golang:1.23-alpine AS build
WORKDIR /src

# Copia primeiro só os arquivos de dependências para aproveitar o cache de
# camadas do Docker: `go mod download` só reroda se go.mod/go.sum mudarem.
COPY app/api/go.mod app/api/go.sum ./
RUN go mod download

COPY app/api/ ./
RUN CGO_ENABLED=0 GOOS=linux GOARCH=amd64 \
    go build -trimpath -ldflags="-s -w" -o /out/api .

FROM gcr.io/distroless/static-debian12:nonroot
COPY --from=build /out/api /api
USER nonroot:nonroot
EXPOSE 8080
ENTRYPOINT ["/api"]
