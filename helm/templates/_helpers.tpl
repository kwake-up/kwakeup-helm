{{/*
Expand the name of the chart.
*/}}
{{- define "kwakeup.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
Release name is included so multiple installs in the same namespace do not collide.
If the release name already contains the chart name it is not duplicated.
*/}}
{{- define "kwakeup.fullname" -}}
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
Common labels — applied to every resource.
Includes helm.sh/chart (version-carrying) and the immutable selector labels.
Do NOT use these in Deployment/StatefulSet spec.selector.matchLabels because
the chart version would change on upgrade and break the selector.
*/}}
{{- define "kwakeup.labels" -}}
helm.sh/chart: {{ printf "%s-%s" .Chart.Name .Chart.Version | quote }}
{{ include "kwakeup.selectorLabels" . }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels — stable across upgrades. Use these in matchLabels and pod
template labels (the pod template may add app.kubernetes.io/version on top).
*/}}
{{- define "kwakeup.selectorLabels" -}}
app.kubernetes.io/name: {{ include "kwakeup.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Determine the ServiceAccount name to use.
*/}}
{{- define "kwakeup.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "kwakeup.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}

{{/*
Name of the bootstrap-admin Secret (managed by this chart).
*/}}
{{- define "kwakeup.bootstrapSecretName" -}}
{{- default (printf "%s-bootstrap" (include "kwakeup.fullname" .)) .Values.app.bootstrapAdmin.existingSecret }}
{{- end }}

{{/*
Name of the OIDC client-secret Secret (managed by this chart).
*/}}
{{- define "kwakeup.oidcSecretName" -}}
{{- default (printf "%s-oidc" (include "kwakeup.fullname" .)) .Values.app.oidc.existingSecret }}
{{- end }}

{{/*
Name of the encryption-key Secret (managed by this chart or provided externally).
*/}}
{{- define "kwakeup.encryptionKeySecretName" -}}
{{- default (printf "%s-encryption" (include "kwakeup.fullname" .)) .Values.app.encryptionKey.existingSecret }}
{{- end }}

{{/*
Name of the SAML SP cert/key Secret (managed by this chart or provided externally).
*/}}
{{- define "kwakeup.samlSecretName" -}}
{{- default (printf "%s-saml" (include "kwakeup.fullname" .)) .Values.app.saml.existingSecret }}
{{- end }}
