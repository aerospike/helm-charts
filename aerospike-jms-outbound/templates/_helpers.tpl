{{/*
Expand the name of the chart.
*/}}
{{- define "aerospike-jms-outbound.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
If release name contains chart name it will be used as a full name.
*/}}
{{- define "aerospike-jms-outbound.fullname" -}}
{{- if .Values.fullnameOverride }}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- $name := default .Chart.Name .Values.nameOverride }}
{{- if contains $name .Release.Name }}
{{- .Release.Name | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}
{{- end }}

{{/*
Create chart name and version as used by the chart label.
*/}}
{{- define "aerospike-jms-outbound.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "aerospike-jms-outbound.labels" -}}
helm.sh/chart: {{ include "aerospike-jms-outbound.chart" . }}
{{ include "aerospike-jms-outbound.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "aerospike-jms-outbound.selectorLabels" -}}
app.kubernetes.io/name: {{ include "aerospike-jms-outbound.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Create the name of the service account to use
*/}}
{{- define "aerospike-jms-outbound.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "aerospike-jms-outbound.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}

{{/*
Connector service/listening port, prefers TLS port if set.
*/}}
{{- define "aerospike-jms-outbound.servicePort" -}}
{{- if ((((.Values.connectorConfig).service).tls).port) }}
{{- (((.Values.connectorConfig).service).tls).port }}
{{- else }}
{{- (((.Values.connectorConfig).service).port) | default 8080 }}
{{- end }}
{{- end }}

{{/*
Connector configuration with required and static values fixed.
*/}}
{{- define "aerospike-jms-outbound.connectorConfig" -}}
{{- if not .Values.connectorConfig}}
{{- fail "connectorConfig must be set in values.yaml" }}
{{- end }}
{{- $merged := dict "connectorConfig" (dict "service" (dict "cluster-name" .Release.Name)) }}
{{- toYaml (merge $merged .Values).connectorConfig }}
{{- end }}