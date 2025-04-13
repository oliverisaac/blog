---
tags:
  - kubernetes
---
In my series "7 days of Kubernetes" I explore setting up [a cheap MiniPC](https://amzn.to/42tenCq) as a single-node Kubernetes cluster using k3s. I walk you through how I went from a bare OS to a kubernetes cluster with Grafana and VictoriaMetrics for observability, argo-cd for continuous delivery, and argo-workflows to automatically build Docker images on push.

## [[Day 0 - Considering a VPS but Selecting a MiniPC]]

In this post I walk through why it makes sense to self host services on a miniPC.
## [[Day 1a - Setting Up k3s]]

A brief explanation of selecting an OS and lightweight kubernetes distribution to deploy.

## [[Day 1b - Deploying Manifests to K3s]]

Exploring how we can quickly deploy manifests to our new k3s cluster. With significant code samples for setting up a git hook.

## [[Day 2a - Ingress with Nginx and Cert-Manager]]

Configuring HTTPS ingresses for both LAN-only and WAN clients. Also, a brief side-track with a script that generates HelmChart manifests for you.
## [[Day 2b - Observability with Grafana and VictoriaMetrics]]

It is important to be able to identify ongoing issues with your nodes or cluster in general. We'll set ourselves up for success by installing monitoring tooling so we can observe system performance when we install more services.

## [[Day 3a - Fixing Partitioning Problems]]

Installing observability tooling immediately paid off: we identified a partitioning misconfiguration! In this post, we walk through fixing the partitioning problem using rescue mode of the installation media.

## [[Day 3b - Sending Emails Through Gmail With Postfix Proxy]]

It's nice to have observability setup, but without alerting we won't know when things are going poorly! In this post we set up a postfix proxy to let us send email alerts to ourselves from Grafana.

## [[Day 4a - Deploy ArgoCD]]

In this post I walk through setting up and deploy the ArgoCD helm chart. ArgoCD will provide the fundamental service for our continuous delivery work to get manifests into our cluster.

## [[Day 4b - ArgoCD triggered by GitHub webhook]]

With ArgoCD set up, we can now configure a github webhook to trigger our ArgoCD deployes instantly rather than needing to wait for a repo sync!

## [[Day 4c - Configuring Git Secrets]]

Putting our entire config into code means that 
# Upcoming posts:


## [[Day 5 - Deploying Argo Workflows]]

## [[Day 6 - Using Argo Workflows to Build a Docker Image on k3s]]

## [[Day 7 - Connecting GitHub Webhook to Argo Workflows To Trigger Builds]]
