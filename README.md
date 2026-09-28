# Mural de Recados — Docker, Kubernetes e Terraform

Entrega do desafio "Do compose ao cluster". O código da aplicação (`app/api`, `app/web`)
não foi alterado — só foram adicionados os Dockerfiles (`app/docker/`) e toda a infra
(`infra/`: Helm chart + Terraform maestro).

## Resumo do fluxo

```
docker-compose.yml   -> só para entender a app localmente (não é a entrega)
app/docker/*.Dockerfile -> imagens de produção (multi-stage, mínimas)
infra/helm/mural/    -> Helm chart (Deployment/StatefulSet/Job/Ingress/Secret/ConfigMap)
infra/terraform/     -> maestro: cria o kind, builda+carrega as imagens, instala o
                         Traefik e faz o deploy do chart — tudo com `terraform apply`
```

## Pré-requisitos para rodar

| Ferramenta | Uso |
|---|---|
| Docker | builda as imagens e roda os nós do kind |
| [kind](https://kind.sigs.k8s.io/) (CLI) | o Terraform chama `kind load docker-image` via `local-exec` |
| [Terraform](https://developer.hashicorp.com/terraform) >= 1.5 | o maestro |
| kubectl / helm (opcional) | só para inspecionar o cluster manualmente |

O cluster em si (`kind_cluster`) é criado pelo *provider* Terraform `tehcyx/kind`, que não
depende do binário `kind` — só o passo de carregar as imagens (`kind load docker-image`)
usa a CLI, por isso ela precisa estar no PATH.

## Rodando

```bash
# 1) (opcional) entender a aplicação rodando localmente
docker compose up --build
# abra http://localhost:8080

# 2) a entrega de verdade: cluster + deploy via Terraform
cd infra/terraform
terraform init
terraform apply          # do zero: cria o cluster, builda/carrega as imagens,
                          # instala o Traefik, aplica o chart
# abra http://mural.localtest.me

terraform apply          # roda de novo: deve dar "No changes."
terraform destroy        # remove tudo (cluster incluído)
```

Também dá para usar `make up` / `make down` (ver `Makefile`).

## Decisões e por quê

### Docker (`app/docker/`)

- **`api.Dockerfile`**: multi-stage. O estágio `build` usa `golang:1.23-alpine` para
  compilar um binário estático (`CGO_ENABLED=0`, `-ldflags="-s -w"`); o estágio final
  parte de `gcr.io/distroless/static-debian12:nonroot` — sem shell, sem package manager,
  roda como usuário não-root. **Tamanho medido nesta máquina:**
  - "Antes" (imagem usada para rodar a API via `go run`, `golang:1.23-alpine`): **246 MB**
  - "Depois" (`mural-api:local`, resultado do Dockerfile): **11.5 MB**
  - Redução de ~95%. Isso significa pull mais rápido no `kind load` e no cluster, e uma
    superfície de ataque bem menor (nenhuma toolchain, nenhum gerenciador de pacotes,
    nenhum shell na imagem final).
- **`web.Dockerfile`**: parte de `nginx:1.27-alpine`, copia os estáticos e o
  `nginx.conf.template` da app (sem alterar nada neles). O proxy de `/api` continua
  parametrizado por `${API_UPSTREAM}` — a mesma imagem serve no compose
  (`API_UPSTREAM=api:8080`) e no cluster (`API_UPSTREAM=<service-da-api>:80`) sem rebuild.
  Tamanho: **48.3 MB**.

### Helm chart (`infra/helm/mural/`)

- **Postgres como `StatefulSet` + `volumeClaimTemplates`** (não `Deployment`): o dado
  precisa sobreviver a um restart do pod; um `Service` headless (`clusterIP: None`) é o
  Service "governante" exigido por um StatefulSet.
- **Credencial nunca hardcoded**: `secret.yaml` usa `required` no `.Values.postgres.password`
  — o chart **falha explicitamente** se ninguém passar uma senha em runtime. O Terraform
  gera a senha com o provider `random` e injeta via `--set` (só existe no state, nunca em
  arquivo versionado). `DATABASE_URL` é montada dentro do Secret, nunca em texto plano num
  `Deployment`/`ConfigMap`.
- **Liveness ≠ Readiness** (`api.yaml`): `livenessProbe` aponta para `/healthz` (processo
  vivo, nunca toca no banco); `readinessProbe` aponta para `/readyz` (só passa com a tabela
  criada). Se as duas apontassem para `/readyz`, o pod entraria em `CrashLoopBackOff` antes
  de a migração terminar.
- **Job de migração NÃO é um hook do Helm** (decisão deliberada, ver comentário em
  `migrate-job.yaml`): um hook `post-install` só roda **depois** que o Helm termina de
  esperar (`--wait`) os Deployments/StatefulSet ficarem `Ready` — mas a API nunca fica
  `Ready` sem a migração ter rodado antes. Isso é um deadlock (o Helm trava esperando a
  API, e o Job que destravaria a API só rodaria depois desse wait, que estoura o timeout).
  Por isso o Job é um recurso comum do chart: sobe junto com o resto, espera o Postgres com
  `pg_isready`, aplica as migrations (idempotentes: `CREATE TABLE IF NOT EXISTS` /
  `INSERT` condicional) e conclui — a API fica `NotReady` até lá e destrava sozinha logo
  em seguida, graças à sua própria `readinessProbe`.
- **`requests`/`limits`** definidos em todos os workloads (Postgres, migração, API, web) —
  ninguém consome o nó inteiro.
- **Tudo parametrizável** via `values.yaml`: imagens/tags, réplicas, host do Ingress,
  storage do Postgres, credencial (injetada em runtime), autoscaling (bônus).

### Terraform (`infra/terraform/`)

- **Providers**: `tehcyx/kind` (cluster), `hashicorp/helm` + `hashicorp/kubernetes`
  (deploy), `hashicorp/random` (senha do Postgres), `hashicorp/null` (build das imagens
  via `local-exec`, já que não existe um provider "docker build" nesta stack).
- **Ingress em `localhost`**: o node do kind recebe o label `ingress-ready=true` (via
  `kubeadm_config_patches`) e port-mappings `80`/`443`; o Traefik é instalado com
  `hostPort` nessas portas e `nodeSelector: ingress-ready=true`. O host usado é
  `mural.localtest.me` (resolve para `127.0.0.1` publicamente — sem mexer em `/etc/hosts`).
- **Idempotência é a peça central**: a tag das imagens (`api_image_tag`/`web_image_tag`)
  é um **hash do conteúdo** do Dockerfile + código-fonte (`sha256`), não uma tag fixa nem
  um timestamp. Isso encadeia tudo:
  - nada mudou → hash igual → `docker build`, `kind load` e `helm_release` não veem diff
    nenhum → segundo `apply` = **`No changes.`**;
  - o código da API muda → hash muda → só os recursos afetados (`build_api_image`,
    `load_api_image`, os valores do `helm_release`) são recriados/reaplicados, disparando
    um rollout — sem tocar no resto (Postgres, Traefik, etc.).
- **`terraform destroy`** remove o release do Helm, o cluster kind (e com ele o namespace,
  os workloads e os PVCs) — nada sobra.

## Bônus

- **HPA**: desligado por padrão (`values.yaml: autoscaling.enabled: false`, chart em
  `templates/hpa.yaml`). Para ligar (requer `metrics-server` no cluster, que o kind não
  traz por padrão):
  ```bash
  kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml
  kubectl patch deployment metrics-server -n kube-system --type=json \
    -p '[{"op":"add","path":"/spec/template/spec/containers/0/args/-","value":"--kubelet-insecure-tls"}]'
  helm upgrade mural infra/helm/mural -n mural --reuse-values --set autoscaling.enabled=true
  kubectl -n mural get hpa -w
  ```
  Em seguida gere carga com `make loadtest` (ou `./infra/loadtest/loadtest.sh`, que usa
  `hey` se disponível ou cai para um loop de `curl` em paralelo) e acompanhe o HPA escalando
  a API.
- **Automação**: `Makefile` na raiz (`make up`, `make down`, `make compose-up`, `make loadtest`).

## Estrutura

```
app/docker/           Dockerfiles (api.Dockerfile, web.Dockerfile)
infra/helm/mural/      Helm chart (Deployment api/web, StatefulSet+PVC postgres,
                        Job de migração, Secret, ConfigMap, Ingress, HPA opcional)
infra/terraform/       main.tf, variables.tf, outputs.tf, versions.tf
infra/loadtest/         script de carga (bônus)
docker-compose.yml     só para entender a app localmente
```
