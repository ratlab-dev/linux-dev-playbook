# commit-echoer

A lightweight Go service packaged into a `scratch` container that periodically prints the Git commit ID every 5 seconds.

## Building
Built via Jenkins Kubernetes ephemeral worker pipeline using Kaniko.
Outputs container image to Harbor: `registry.ratlab.dev:8443/library/commit-echoer:<commit-sha>`.

## Builds
Automated CI/CD build verified via Jenkins Kubernetes ephemeral agent pipeline.
