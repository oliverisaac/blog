> [!note]
> This post is part of my [[7 Days Of Kubernetes]] where I explore setting up [a cheap MiniPC](https://amzn.to/42tenCq) as a single-node Kubernetes cluster using k3s.

In the previous posts we've set up infrastructure, like [[Day 4a - Deploy ArgoCD|argocd]] and [transcrypt]([[Day 4c - Configuring Git Secrets]]), to let us efficiently deploy services to [our single node k3s cluster]([[Day 1a - Setting Up k3s]]). Today we'll be setting up argo-workflows to give us infrastructure to build fresh artifacts.

Over the next 3 posts we will:
- set up argo-workflows and run a simple workflow
- create a workflow to build and push a docker image
- configure a workflow event binding to trigger our workflow on events from github

Let's dive in!

# What is Argo-Workflows?

[Argo Workflows](https://argoproj.github.io/workflows/) is a tool built by the same people who made ArgoCD. It allows you to set up workflows that can be dynamically triggered and which run in your kubernetes cluster.

As an example, you could set up a workflow that has one container which pulls down some source code and then a second container which [uses trufflehog to scan the source code for secrets](https://github.com/trufflesecurity/trufflehog). 

Or, as another example, I use argo-workflows to publish this blog. I push the source to github, then argo-workflows pulls the code down, extracts the blog posts, and pushes the content to [my blog repo](https://github.com/oliverisaac/blog).

# Setting Up Argo Workflows

By this point in our series, you've set up enough helm charts that you should be able to get this going without needing custom values files.

You can get [the argo-workflows helm chart](https://artifacthub.io/packages/helm/argo/argo-workflows) from artifacthub and then read through the values, configuring as you see fit. I've started off with some basic options:

```yaml

---
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: argo-workflows
  namespace: argocd
spec:
  project: default
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
    - CreateNamespace=true
  destination:
    name: "in-cluster"
    namespace: argo-workflows
  source:
    repoURL: https://argoproj.github.io/argo-helm
    chart: argo-workflows
    targetRevision: 0.45.12
    helm:
      valuesObject:
            # Set up ingress to the service:
            server:
                ingress:
                    enabled: true
                    ingressClassName: "internal"
                    hosts:
                    - workflows.internal.example.com
            controller:
                workflowNamespaces:
                - argo-workflow-jobs
                
            # create the namespace for our jobs
            extraObjects: 
              - kind: Namespace
                apiVersion: v1
                metadata:
                  name: argo-workflow-jobs
```

In this config we set up an ingress to access arog-workflows and we also set up a namespace into which we can deploy a workflow. 


> [!warning] Wildly Insecure Defaults
> Note that the default config for argo-workflows does not have any authentication so anybody that can route traffic to the workflows server can submit jobs.
> There is a config option to set up oauth but we are not using that right now because my threat model for this single node cluster is that we trust traffic inside the network. 
> If you are setting up argo-workflows in a more broadly accessible way then you should absolutely configure some form of SSO.


# Testing It Out

Now that we have a argo-workflows up and running we can deploy a simple workflow. There are [a lot of examples in the argo-workflows github](https://github.com/argoproj/argo-workflows/tree/main/examples) but we'll start off with a very simple hello world example:

```yaml
# This template demonstrates a steps template and how to control sequential vs. parallel steps.
# In this example, the hello1 completes before the hello2a, and hello2b steps, which run in parallel.
apiVersion: argoproj.io/v1alpha1
kind: Workflow
metadata:
  name: steps-example
  namespace: argo-workflow-jobs
spec:
  entrypoint: hello-hello-hello
  templates:
  - name: hello-hello-hello
    steps:
    - - name: hello1
        template: print-message
        arguments:
          parameters: [{name: message, value: "hello1"}]
    - - name: hello2a
        template: print-message
        arguments:
          parameters: [{name: message, value: "hello2a"}]
      - name: hello2b
        template: print-message
        arguments:
          parameters: [{name: message, value: "hello2b"}]

  - name: print-message
    inputs:
      parameters:
      - name: message
    container:
      image: busybox
      command: [echo]
      args: ["{{inputs.parameters.message}}"]
```

You can either add this workflow to your argocd manifests or apply it directly to the cluster. Either way, once this is deployed you can visit the argo-workflows UI and you should see that your workflow is running!

![[Screenshot 2025-04-16 at 7.27.12 PM.png]]

# Next Steps

Now that we have argo workflows setup, we want to use this to build containers. Check out the next post where we do just that: [[Day 6 - Using Argo Workflows to Build a Docker Image on k3s]] 