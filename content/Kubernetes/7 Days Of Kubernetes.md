---
tags:
  - kubernetes
---
In my series "7 days of Kubernetes" I explore setting up [a cheap MiniPC](https://amzn.to/42tenCq) as a single-node Kubernetes cluster using k3s. I walk you through how I went from a bare OS to a kuberntes cluster with Grafana and VictoriaMetrics for observability, argo-cd for continuous delivery, and argo-workflows to automatically build Docker images on push.

# [[Day 1a - Setting Up k3s]]

A brief explanation of selecting an OS and lightweight kubernetes distribution to deploy.

# [[Day 1b - Deploying Manifests to K3s]]

Exploring how we can quickly deploy manifests to our new k3s cluster. With significant code samples for setting up a git hook.

# [[Day 2a - Ingress with Nginx and Cert-Manager]]

Configuring HTTPS ingresses for both LAN-only and WAN clients. Also, a brief side-track with a script that generates HelmChart manifests for you.
# [[Day 2b - Observability with Grafana and VictoriaMetrics]]

# [[Day 3a - Fixing Partitioning Problems]]


# [[Day 3c - Egress with Postfix]]

# [[Day 4a - Configure ArgoCD]]

# [[Day 4b - ArgoCD triggered by GitHub webhook]]

# [[Day 4c - Configuring Git Secrets]]

# [[Day 5 - Deploying Argo Workflows]]

# [[Day 6 - Using Argo Workflows to Build a Docker Image on k3s]]

# [[Day 7 - Connecting GitHub Webhook to Argo Workflows To Trigger Builds]]
