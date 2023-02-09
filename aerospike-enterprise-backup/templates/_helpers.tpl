{{/*
Expand the name of the chart.
*/}}
{{- define "aerospike-enterprise-backup.name" -}}
{{- default $.Chart.Name $.Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
If release name contains chart name it will be used as a full name.
*/}}
{{- define "aerospike-enterprise-backup.fullname" -}}
{{- if .Values.fullnameOverride }}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- .Chart.Name | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}

{{/*
Create chart name and version as used by the chart label.
*/}}
{{- define "aerospike-enterprise-backup.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "aerospike-enterprise-backup.labels" -}}
helm.sh/chart: {{ include "aerospike-enterprise-backup.chart" . }}
{{ include "aerospike-enterprise-backup.selectorLabels" . }}
app.kubernetes.io/version: {{ include "aerospike-enterprise-backup.version" . | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/part-of: {{ include "aerospike-enterprise-backup.fullname" . | quote }}
{{- end }}

{{- define "aerospike-enterprise-backup.version" -}}
{{- if and (hasKey .component "image") (.component.image.tag) -}}
{{ .component.image.tag }}
{{- else -}}
{{- default .Chart.AppVersion .Values.image.tag | trunc 63 | trimSuffix "-" -}}
{{- end -}}
{{- end -}}
{{/*
Selector labels
*/}}
{{- define "aerospike-enterprise-backup.selectorLabels" -}}
app.kubernetes.io/name: {{ .component.name | trunc 63 | trimSuffix "-" }}
app.kubernetes.io/instance: {{ $.Release.Name }}
{{- end }}

{{- define "elk-annotations" -}}
co.elastic.logs/enabled: {{ true | quote }}
{{- end }}
{{/*
Create the name of the service account to use
*/}}
{{- define "aerospike-enterprise-backup.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "aerospike-enterprise-backup.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}

{{- define "smd-handler.config" -}}
backendUri: {{ .Chart.Name }}
storageProviderUri: {{ .Chart.Name }}
{{- end -}}

{{- define "aerospike-xdr-proxy.config" -}}
service:
  port: {{ $.Values.xdrtransformer.config.service.port | quote }}
  address: {{ $.Values.xdrtransformer.config.service.address }}
  manage:
    address: {{ $.Values.xdrtransformer.config.service.manage.address }}
    port: {{ $.Values.xdrtransformer.config.service.manage.port }}
aerospike:
  seeds:
    - {{ $.Values.backupcluster.name }}.{{ $.Release.Namespace }}.svc.cluster.local:
       port: {{ $.Values.backupcluster.address.port.number }}
  credentials:
    username: {{ $.Values.backupcluster.auth.username }}
    password-file: /etc/config/pswd.txt
logging:
  enable-console-logging: {{ $.Values.xdrtransformer.config.logging.enableConsoleLogging }}
  levels:
    root: info
  file: {{ $.Values.xdrtransformer.config.logging.file | quote }}
  ticker-interval: {{ $.Values.xdrtransformer.config.logging.tickerInterval | quote }}
message-transformer:
  class: com.aerospike.pitr.transformer.RecordTransformer

{{- end -}}

{{- define "initContainer.wait.rest-backend" -}}
- name: "init-wait-rest-backend"
  image: alpine/curl
  command: ["/bin/sh", "-c", "while true; do echo 'Reaching rest-backend...'; curl --silent {{ $.Values.restbackend.name }}.{{ $.Release.Namespace }}.svc.cluster.local:{{ $.Values.restbackend.port.number }}/health; if [ $? -eq 0 ]; then echo 'Reached rest-backend'; break; else echo 'Retry in 3 seconds...'; sleep 3s; fi done"]
{{- end -}}

{{- define "initContainer.wait.authenticator" -}}
- name: "init-wait-authenticator"
  image: alpine/curl
  command: ["/bin/sh", "-c", "while true; do echo 'Reaching authenticator...'; curl --silent {{ $.Values.authenticator.name }}.{{ $.Release.Namespace }}.svc.cluster.local:{{ $.Values.authenticator.port.number }}/health; if [ $? -eq 0 ]; then echo 'Reached authenticator'; break; else echo 'Retry in 3 seconds...'; sleep 3s; fi done"]
{{- end -}}

{{- define "initContainer.wait.storage-provider" -}}
- name: "init-wait-storage-provider"
  image: alpine/curl
  command: ["/bin/sh", "-c", "while true; do echo 'Reaching storage-provider...'; curl --silent {{ $.Values.storageprovider.name }}.{{ $.Release.Namespace }}.svc.cluster.local:{{ $.Values.storageprovider.port.number }}/health; if [ $? -eq 0 ]; then echo 'Reached storage-provider'; break; else echo 'Retry in 3 seconds...'; sleep 3s; fi done"]
{{- end -}}

{{- define "initContainer.wait.xdr-transformer" }}
- name: "init-wait-xdr-transformer"
  image: alpine/curl
  command: ["/bin/sh", "-c", "while true; do echo 'Reaching xdr-transformer...'; curl --silent {{ $.Values.xdrtransformer.name }}.{{ $.Release.Namespace }}.svc.cluster.local:{{ $.Values.xdrtransformer.config.service.manage.port }}/manage/rest/v1/logging; if [ $? -eq 0 ]; then echo 'Reached xdr-transformer'; break; else echo 'Retry in 3 seconds...'; sleep 3s; fi done"]
{{- end }}

{{- define "get-image" -}}
{{ $version := include "aerospike-enterprise-backup.version" . }}
{{- if .component.image.repository -}}
{{ printf "%s:%s" .component.image.repository $version }}
{{- else -}}
{{ printf "%s/%s:%s" .Values.image.repository .component.name $version }}
{{- end -}}
{{- end -}}

{{- define "get-k8s-cli-image" -}}
{{ printf "alpine/k8s:%v" (trimPrefix "v" (split "-" $.Capabilities.KubeVersion.Version)._0) }}
{{- end -}}

{{- define "imagePullSecrets" }}
{{- if .Values.aws.ecrtokenissuer.enabled }}
imagePullSecrets:
  - name: {{ .Values.aws.ecrtokenissuer.secretname }}
{{- end }}
{{- end }}