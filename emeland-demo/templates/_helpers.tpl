{{/*
Expand the name of the chart.
*/}}
{{- define "emeland-demo.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
If release name contains chart name it will be used as a full name.
*/}}
{{- define "emeland-demo.fullname" -}}
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
{{- define "emeland-demo.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "emeland-demo.labels" -}}
helm.sh/chart: {{ include "emeland-demo.chart" . }}
{{ include "emeland-demo.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "emeland-demo.selectorLabels" -}}
app.kubernetes.io/name: {{ include "emeland-demo.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Create the name of the service account to use
*/}}
{{- define "emeland-demo.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "emeland-demo.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}

{{/*
Web UI server container image
*/}}
{{- define "emeland-demo.serverImage" -}}
{{- printf "%s/%s:%s" .Values.image.server.registry .Values.image.server.repository (.Values.image.server.tag | default .Chart.AppVersion) -}}
{{- end }}

{{/*
In-cluster web UI server base URL (no trailing slash).
*/}}
{{- define "emeland-demo.serverInternalUrl" -}}
{{- printf "http://%s-server:%v" (include "emeland-demo.fullname" .) .Values.service.port -}}
{{- end }}

{{/*
In-cluster modelsrv API base URL for sensor event push (must end with /api/).
*/}}
{{- define "emeland-demo.modelsrvApiUrl" -}}
{{- printf "%s/api/" (include "emeland-demo.serverInternalUrl" .) -}}
{{- end }}

{{/*
In-cluster phase0 filter API base URL (must end with /api/).
*/}}
{{- define "emeland-demo.filterApiUrl" -}}
{{- printf "http://%s-filter:%v/api/" (include "emeland-demo.fullname" .) .Values.filter.service.port -}}
{{- end }}

{{/*
Comma-separated SUBSCRIBERS for modelsrv server startup registration.
*/}}
{{- define "emeland-demo.filterSubscribers" -}}
{{- $urls := list -}}
{{- range .Values.filter.downstreamSubscribers -}}
{{- $urls = append $urls (tpl . $) -}}
{{- end -}}
{{- join "," $urls -}}
{{- end }}

{{/*
modelsrv filter container image (phase0 integrity checks)
*/}}
{{- define "emeland-demo.filterImage" -}}
{{- printf "%s/%s:%s" .Values.image.filter.registry .Values.image.filter.repository (.Values.image.filter.tag | default .Chart.AppVersion) -}}
{{- end }}

{{/*
Tools container image
*/}}
{{- define "emeland-demo.toolsImage" -}}
{{- printf "%s/%s:%s" .Values.image.tools.registry .Values.image.tools.repository (.Values.image.tools.tag | default .Chart.AppVersion) -}}
{{- end }}

{{/*
Git server container image
*/}}
{{- define "emeland-demo.gitserverImage" -}}
{{- printf "%s/%s:%s" .Values.image.gitserver.registry .Values.image.gitserver.repository (.Values.image.gitserver.tag | default .Chart.AppVersion) -}}
{{- end }}

{{/*
Git sensor container image
*/}}
{{- define "emeland-demo.gitsensorImage" -}}
{{- printf "%s/%s:%s" .Values.image.gitsensor.registry .Values.image.gitsensor.repository (.Values.image.gitsensor.tag | default .Chart.AppVersion) -}}
{{- end }}

{{/*
OCI registry sensor container image
*/}}
{{- define "emeland-demo.ociregistrysensorImage" -}}
{{- printf "%s/%s:%s" .Values.image.ociregistrysensor.registry .Values.image.ociregistrysensor.repository (.Values.image.ociregistrysensor.tag | default .Chart.AppVersion) -}}
{{- end }}

{{/*
In-cluster SSH URL for the baked test-gitsensor-target bare repository
*/}}
{{- define "emeland-demo.gitRepoSSH" -}}
{{- printf "git@%s-git:%s" (include "emeland-demo.fullname" .) .Values.gitsensor.repoPath -}}
{{- end }}

{{/*
Overview (homepage) resource name
*/}}
{{- define "emeland-demo.overviewName" -}}
{{- printf "%s-homepage" (include "emeland-demo.fullname" .) -}}
{{- end }}

{{/*
Gateway name. Defaults to "gateway" but can be overridden. Used by the Gateway
template and as the default parentRef for all HTTPRoutes, so they always agree.
*/}}
{{- define "emeland-demo.gatewayName" -}}
{{- .Values.gateway.name | default "gateway" -}}
{{- end }}

{{/*
Overview (homepage) selector labels
*/}}
{{- define "emeland-demo.overviewSelectorLabels" -}}
app.kubernetes.io/name: homepage
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Overview (homepage) common labels
*/}}
{{- define "emeland-demo.overviewLabels" -}}
helm.sh/chart: {{ include "emeland-demo.chart" . }}
{{ include "emeland-demo.overviewSelectorLabels" . }}
app.kubernetes.io/component: overview
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Overview (homepage) container image
*/}}
{{- define "emeland-demo.overviewImage" -}}
{{- printf "%s/%s:%s" .Values.overview.image.registry .Values.overview.image.repository .Values.overview.image.tag -}}
{{- end }}

{{/*
Overview (homepage) config files (the ConfigMap data block). Defined once so
the Deployment can checksum it and roll the pod when the config changes.
*/}}
{{- define "emeland-demo.overviewConfig" -}}
# Cluster mode + Gateway API discovery: homepage watches HTTPRoutes annotated
# with gethomepage.dev/enabled and builds service tiles from them.
kubernetes.yaml: |
  mode: cluster
  # Gateway API discovery only. Ingress discovery is left disabled so homepage
  # neither queries ingresses nor needs RBAC for them.
  gateway: true
  ingress: false
settings.yaml: |
  title: {{ .Values.overview.title | quote }}
  # Group tiles by the gethomepage.dev/group annotation on each route.
  layout:
    EmELand:
      style: row
      columns: 2
    Observability:
      style: row
      columns: 3
widgets.yaml: |
  # Cluster CPU/memory. Needs the Metrics API (metrics-server), which the
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
