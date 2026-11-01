# Ratlab Jenkins Shared Pipeline Library

Reusable Jenkins pipeline steps and templates for building and deploying microservices on Kubernetes.

## Functions Provided
- `buildAppImage(Map config)`: Ephemeral Kubernetes Kaniko builder that builds Dockerfiles and publishes to Harbor OCI registry.
