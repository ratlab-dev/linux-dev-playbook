def call(Map config = [:]) {
    def appName = config.get('appName', 'app')
    def imageRepo = config.get('imageRepo', "library/${appName}")
    def registryHost = config.get('registryHost', 'registry.ratlab.dev:8443')

    pipeline {
        agent {
            kubernetes {
                cloud 'giant-cluster'
                defaultContainer 'kaniko'
                yaml """
apiVersion: v1
kind: Pod
metadata:
  labels:
    jenkins-agent: kaniko-builder
spec:
  serviceAccountName: jenkins-agent
  dnsConfig:
    options:
    - name: ndots
      value: "1"
  containers:
  - name: jnlp
    image: jenkins/inbound-agent:latest
    workingDir: /home/jenkins/agent
    env:
    - name: REMOTING_OPTS
      value: "-noCertificateCheck"
    - name: GIT_SSL_NO_VERIFY
      value: "true"
    resourceRequestCpu: 100m
    resourceLimitCpu: 500m
    resourceRequestMemory: 128Mi
    resourceLimitMemory: 512Mi
  - name: kaniko
    image: gcr.io/kaniko-project/executor:debug
    command:
    - /busybox/cat
    tty: true
    workingDir: /home/jenkins/agent
    resourceRequestCpu: 200m
    resourceLimitCpu: 1000m
    resourceRequestMemory: 256Mi
    resourceLimitMemory: 1024Mi
"""
            }
        }
        triggers {
            pollSCM('* * * * *')
        }
        stages {
            stage('Prepare Workspace & Auth') {
                steps {
                    container('kaniko') {
                        sh """#!/busybox/sh
set -e
echo "Configuring Harbor registry authentication..."
mkdir -p /kaniko/.docker
AUTH=\$(echo -n "admin:admin" | /busybox/base64 | tr -d '\\n')
cat <<EOF > /kaniko/.docker/config.json
{
  "auths": {
    "${registryHost}": {
      "auth": "\${AUTH}"
    }
  }
}
EOF
"""
                    }
                }
            }
            stage('Build & Push Container Image') {
                steps {
                    container('kaniko') {
                        sh """#!/busybox/sh
set -e
COMMIT_FULL=\${GIT_COMMIT:-manual-\${BUILD_NUMBER}}
COMMIT_SHA=\$(echo "\${COMMIT_FULL}" | /busybox/cut -c1-7)
echo "Building scratch image for ${appName} with commit SHA: \${COMMIT_SHA} (\${COMMIT_FULL})"

DESTINATIONS="--destination=${registryHost}/${imageRepo}:\${COMMIT_SHA}"
if [ "\${COMMIT_FULL}" != "\${COMMIT_SHA}" ]; then
  DESTINATIONS="\${DESTINATIONS} --destination=${registryHost}/${imageRepo}:\${COMMIT_FULL}"
fi
DESTINATIONS="\${DESTINATIONS} --destination=${registryHost}/${imageRepo}:latest"

/kaniko/executor \\
  --context=dir://\${WORKSPACE} \\
  --dockerfile=\${WORKSPACE}/Dockerfile \\
  \${DESTINATIONS} \\
  --build-arg=COMMIT_ID=\${COMMIT_SHA} \\
  --ignore-path=/product_uuid \\
  --ignore-path=/product_name \\
  --skip-tls-verify
"""
                    }
                }
            }
        }
    }
}
