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
  containers:
  - name: jnlp
    image: jenkins/inbound-agent:latest
    workingDir: /home/jenkins/agent
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
COMMIT=\${GIT_COMMIT:-manual-\${BUILD_NUMBER}}
SHORT_COMMIT=\$(echo "\${COMMIT}" | /busybox/cut -c1-8)
echo "Building scratch image for ${appName} with commit: \${SHORT_COMMIT}"

/kaniko/executor \\
  --context=dir://\${WORKSPACE} \\
  --dockerfile=\${WORKSPACE}/Dockerfile \\
  --destination=${registryHost}/${imageRepo}:\${SHORT_COMMIT} \\
  --destination=${registryHost}/${imageRepo}:latest \\
  --build-arg=COMMIT_ID=\${SHORT_COMMIT} \\
  --skip-tls-verify
"""
                    }
                }
            }
        }
    }
}
