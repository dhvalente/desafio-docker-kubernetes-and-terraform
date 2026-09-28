# Maestro: cria o cluster kind, disponibiliza as imagens (docker build +
# kind load docker-image via local-exec), instala o Traefik como Ingress
# Controller e implanta o chart do Mural. Um único `terraform apply` sai do
# zero até a aplicação respondendo; um segundo `apply` não deve mudar nada
# (idempotência via tags derivadas de hash de conteúdo, não de timestamps).

provider "kind" {}

resource "kind_cluster" "this" {
  name           = var.cluster_name
  wait_for_ready = true

  kind_config {
    kind        = "Cluster"
    api_version = "kind.x-k8s.io/v1alpha4"

    node {
      role = "control-plane"

      # Label exigido pelo Ingress controller (nodeSelector do Traefik,
      # abaixo) e port-mappings 80/443 para o Ingress responder em localhost
      # sem mexer em /etc/hosts (usamos *.localtest.me).
      kubeadm_config_patches = [
        <<-EOT
        kind: InitConfiguration
        nodeRegistration:
          kubeletExtraArgs:
            node-labels: "ingress-ready=true"
        EOT
      ]

      extra_port_mappings {
        container_port = 80
        host_port      = 80
        protocol       = "TCP"
      }
      extra_port_mappings {
        container_port = 443
        host_port      = 443
        protocol       = "TCP"
      }
    }
  }
}

provider "kubernetes" {
  host                   = kind_cluster.this.endpoint
  client_certificate     = kind_cluster.this.client_certificate
  client_key             = kind_cluster.this.client_key
  cluster_ca_certificate = kind_cluster.this.cluster_ca_certificate
}

provider "helm" {
  kubernetes {
    host                   = kind_cluster.this.endpoint
    client_certificate     = kind_cluster.this.client_certificate
    client_key             = kind_cluster.this.client_key
    cluster_ca_certificate = kind_cluster.this.cluster_ca_certificate
  }
}

# Senha do Postgres: gerada pelo Terraform, nunca commitada em values.yaml.
# Vive só no state e é injetada no release via --set (helm_release.values).
resource "random_password" "db" {
  length  = 20
  special = false
}

# Ingress Controller. hostPort 80/443 nos pods do Traefik + node com label
# ingress-ready=true (acima) é o jeito padrão de expor um Ingress em
# localhost num cluster kind.
resource "helm_release" "traefik" {
  name             = "traefik"
  repository       = "https://traefik.github.io/charts"
  chart            = "traefik"
  version          = var.traefik_chart_version
  namespace        = "traefik"
  create_namespace = true
  wait             = true
  timeout          = 300

  values = [
    yamlencode({
      ports = {
        web       = { hostPort = 80 }
        websecure = { hostPort = 443 }
      }
      service = {
        spec = {
          type = "NodePort"
        }
      }
      nodeSelector = {
        "ingress-ready" = "true"
      }
      tolerations = [
        {
          key      = "node-role.kubernetes.io/control-plane"
          operator = "Exists"
          effect   = "NoSchedule"
        }
      ]
    })
  ]

  depends_on = [kind_cluster.this]
}

locals {
  repo_root = abspath("${path.module}/../..")

  api_dockerfile_sha = filesha256("${local.repo_root}/app/docker/api.Dockerfile")
  api_src_sha         = sha256(join("", [for f in sort(fileset("${local.repo_root}/app/api", "**")) : filesha256("${local.repo_root}/app/api/${f}")]))
  # Tag derivada do conteúdo (Dockerfile + fonte): muda só quando algo que
  # afeta a imagem realmente muda. Isso é o que faz o pipeline inteiro ser
  # idempotente — build, load no kind e helm_release só disparam de novo
  # quando essa tag muda; se nada mudou, um segundo apply não recria nada.
  api_image_tag = substr(sha256("${local.api_dockerfile_sha}-${local.api_src_sha}"), 0, 12)

  web_dockerfile_sha = filesha256("${local.repo_root}/app/docker/web.Dockerfile")
  web_src_sha         = sha256(join("", [for f in sort(fileset("${local.repo_root}/app/web", "**")) : filesha256("${local.repo_root}/app/web/${f}")]))
  web_image_tag = substr(sha256("${local.web_dockerfile_sha}-${local.web_src_sha}"), 0, 12)
}

# --- Build das imagens -------------------------------------------------
# null_resource porque não há um provider "docker build" nesta stack
# (kind/helm/kubernetes, conforme pedido); o local-exec só roda de novo
# quando a tag (derivada do hash do conteúdo) muda.

resource "null_resource" "build_api_image" {
  triggers = {
    image = "${var.api_image}:${local.api_image_tag}"
  }

  provisioner "local-exec" {
    working_dir = local.repo_root
    command     = "docker build -f app/docker/api.Dockerfile -t ${var.api_image}:${local.api_image_tag} ."
  }
}

resource "null_resource" "build_web_image" {
  triggers = {
    image = "${var.web_image}:${local.web_image_tag}"
  }

  provisioner "local-exec" {
    working_dir = local.repo_root
    command     = "docker build -f app/docker/web.Dockerfile -t ${var.web_image}:${local.web_image_tag} ."
  }
}

# --- Carrega as imagens no cluster kind ---------------------------------
# Via local-exec com a CLI `kind` (o provider tem um recurso nativo
# "kind_load" equivalente, mas ele só existe em desenvolvimento — não foi
# lançado em nenhuma versão publicada, então não dá para depender dele).
# Trigger inclui a identidade do cluster (client_certificate muda sempre
# que o cluster é recriado) além da tag da imagem: garante o reload tanto
# quando o código muda quanto quando o cluster é recriado do zero, sem
# rodar à toa quando nenhum dos dois mudou.

resource "null_resource" "load_api_image" {
  triggers = {
    image   = "${var.api_image}:${local.api_image_tag}"
    cluster = kind_cluster.this.client_certificate
  }

  provisioner "local-exec" {
    command = "kind load docker-image ${var.api_image}:${local.api_image_tag} --name ${var.cluster_name}"
  }

  depends_on = [kind_cluster.this, null_resource.build_api_image]
}

resource "null_resource" "load_web_image" {
  triggers = {
    image   = "${var.web_image}:${local.web_image_tag}"
    cluster = kind_cluster.this.client_certificate
  }

  provisioner "local-exec" {
    command = "kind load docker-image ${var.web_image}:${local.web_image_tag} --name ${var.cluster_name}"
  }

  depends_on = [kind_cluster.this, null_resource.build_web_image]
}

# --- Deploy do chart ------------------------------------------------------

resource "helm_release" "mural" {
  name             = "mural"
  chart            = "${path.module}/../helm/mural"
  namespace        = var.namespace
  create_namespace = true
  wait             = true
  timeout          = 300

  values = [
    yamlencode({
      image = {
        api = { repository = var.api_image, tag = local.api_image_tag }
        web = { repository = var.web_image, tag = local.web_image_tag }
      }
      api      = { replicaCount = var.api_replicas }
      web      = { replicaCount = var.web_replicas }
      postgres = { password = random_password.db.result }
      ingress  = { host = var.ingress_host }
    })
  ]

  depends_on = [
    helm_release.traefik,
    null_resource.load_api_image,
    null_resource.load_web_image,
  ]
}
