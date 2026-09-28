variable "cluster_name" {
  description = "Nome do cluster kind"
  type        = string
  default     = "mural"
}

variable "namespace" {
  description = "Namespace onde o chart do Mural é implantado"
  type        = string
  default     = "mural"
}

variable "ingress_host" {
  description = "Host usado pelo Ingress (resolve para 127.0.0.1 via *.localtest.me)"
  type        = string
  default     = "mural.localtest.me"
}

variable "api_image" {
  description = "Nome (repository) da imagem da API carregada no kind"
  type        = string
  default     = "mural-api"
}

variable "web_image" {
  description = "Nome (repository) da imagem do front carregada no kind"
  type        = string
  default     = "mural-web"
}

variable "api_replicas" {
  type    = number
  default = 2
}

variable "web_replicas" {
  type    = number
  default = 2
}

variable "traefik_chart_version" {
  description = "Versão do chart oficial do Traefik (ingress controller)"
  type        = string
  default     = "41.6.0"
}
