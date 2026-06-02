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
In-cluster SSH URL for the baked test-gitsensor-target bare repository
*/}}
{{- define "emeland-demo.gitRepoSSH" -}}
{{- printf "git@%s-git:%s" (include "emeland-demo.fullname" .) .Values.gitsensor.repoPath -}}
{{- end }}
