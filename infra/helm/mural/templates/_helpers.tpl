{{- define "mural.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "mural.fullname" -}}
{{- if .Values.fullnameOverride -}}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- $name := default .Chart.Name .Values.nameOverride -}}
{{- if contains $name .Release.Name -}}
{{- .Release.Name | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" -}}
{{- end -}}
{{- end -}}
{{- end -}}

{{- define "mural.labels" -}}
app.kubernetes.io/name: {{ include "mural.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
helm.sh/chart: {{ .Chart.Name }}-{{ .Chart.Version }}
{{- end -}}

{{- define "mural.selectorLabels" -}}
app.kubernetes.io/name: {{ include "mural.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}

{{- define "mural.postgresSecretName" -}}
{{- printf "%s-postgres" (include "mural.fullname" .) -}}
{{- end -}}

{{- define "mural.postgresServiceName" -}}
{{- printf "%s-postgres" (include "mural.fullname" .) -}}
{{- end -}}

{{- define "mural.apiServiceName" -}}
{{- printf "%s-api" (include "mural.fullname" .) -}}
{{- end -}}

{{- define "mural.webServiceName" -}}
{{- printf "%s-web" (include "mural.fullname" .) -}}
{{- end -}}
