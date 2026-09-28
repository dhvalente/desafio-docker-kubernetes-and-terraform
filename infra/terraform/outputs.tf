output "cluster_name" {
  description = "Nome do cluster kind provisionado"
  value       = kind_cluster.this.name
}

output "namespace" {
  description = "Namespace onde o Mural foi implantado"
  value       = var.namespace
}

output "mural_url" {
  description = "URL do Mural de Recados (kind mapeia a porta 80 do host para o Ingress)"
  value       = "http://${var.ingress_host}"
}
