{{/*
Chart name.
*/}}
{{- define "emeland-platform.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Fully qualified app name.
*/}}
{{- define "emeland-platform.fullname" -}}
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

{{- define "emeland-platform.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "emeland-platform.labels" -}}
helm.sh/chart: {{ include "emeland-platform.chart" . }}
{{ include "emeland-platform.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{- define "emeland-platform.selectorLabels" -}}
app.kubernetes.io/name: {{ include "emeland-platform.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Gateway name. Defaults to "gateway" but can be overridden. Used by the Gateway
template and as the default parentRef for the platform's own HTTPRoutes; the
EmELand app chart references the same name.
*/}}
{{- define "emeland-platform.gatewayName" -}}
{{- .Values.gateway.name | default "gateway" -}}
{{- end }}

{{/*
Overview (homepage) resource name
*/}}
{{- define "emeland-platform.overviewName" -}}
{{- printf "%s-homepage" (include "emeland-platform.fullname" .) -}}
{{- end }}

{{- define "emeland-platform.overviewSelectorLabels" -}}
app.kubernetes.io/name: homepage
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{- define "emeland-platform.overviewLabels" -}}
helm.sh/chart: {{ include "emeland-platform.chart" . }}
{{ include "emeland-platform.overviewSelectorLabels" . }}
app.kubernetes.io/component: overview
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{- define "emeland-platform.overviewImage" -}}
{{- printf "%s/%s:%s" .Values.overview.image.registry .Values.overview.image.repository .Values.overview.image.tag -}}
{{- end }}

{{/*
Overview (homepage) config files (the ConfigMap data block). Defined once so
the Deployment can checksum it and roll the pod when the config changes.
*/}}
{{- define "emeland-platform.overviewConfig" -}}
# Cluster mode + Gateway API discovery: homepage watches HTTPRoutes annotated
# with gethomepage.dev/enabled and builds service tiles from them.
kubernetes.yaml: |
  mode: cluster
  gateway: true
  ingress: false
settings.yaml: |
  title: {{ .Values.overview.title | quote }}
  layout:
    EmELand:
      style: row
      columns: 2
    Observability:
      style: row
      columns: 3
widgets.yaml: |
  # Cluster CPU/memory. Needs the Metrics API (metrics-server), which this
  # chart installs by default (see metrics-server.enabled).
  - kubernetes:
      cluster:
        show: true
        cpu: true
        memory: true
        showLabel: true
        label: cluster
      nodes:
        show: false
  - search:
      provider: duckduckgo
      target: _blank
services.yaml: ""
bookmarks.yaml: ""
custom.css: ""
custom.js: ""
docker.yaml: ""
{{- end }}
