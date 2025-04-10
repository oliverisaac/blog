If you are planning to build container images in containerd there are two big options:

- [Kaniko](https://github.com/GoogleContainerTools/kaniko)
- Nested Containers (colloquially "docker-in-docker" )

# Kaniko

Kaniko, [a tool release by Google](https://github.com/GoogleContainerTools/kaniko), allows you to build container images inside a running containerd or docker container. This is a nice way to improve the security posture of your build environment. 

Layer caching in Kaniko is handled differently than you might be used to with docker. You need to pre-warm the layer cache on every run or use remote layer caching. This is workable and a good solution if you have multiple build nodes but, on a single node k3s cluster like I'm running, I'm okay with the security trade-off to reduce the IO overhead.

# Nested Containers (Docker-in-Docker)

Nested containers are a popular option for building containers inside kubernetes. One major downside to nested containers is that there are significant security risks. By allowing the container to talk with the underlying container engine a malicious actor or inadvertent command can wreck havoc on any other running containers. 

In the case of a single-node k3s cluster like I'm running, the big benefit of nested containers is that the docker build cache will be always available and really speed up the build process.

## Requirements

### Mount these files in the container

- `/run/buildkit/buildkitd.sock`
- `/run/k3s/containerd/containerd.sock`
- `/usr/local/bin/nerdctl`
- `/usr/local/bin/buildctl`
- `/usr/bin/aa-exec`

### Run the container as privileged

You can do this in nerdctl with `--privileged`

Or you can do this in kubernetes by setting `.securityContext.privileged = true` in the container spec.

### Set `CONTAINERD_NAMESPACE=k8s.io`

You will need to set the containerd namespace to use the `k8s.io` namespace if you want the images you build to be immediately available to your kubernetes cluster. 

> [!warning]
> You might think you can increase the security of your nested container deployment by using a different namespace for building. However, keep in mind that a malicious actor can just change the namespace using a command flag (`--namespace`) or redefining the `CONTAINERD_NAMESPACE`. 

## Example `nerdctl` command

Below is an example command running `nerdctl ps` from inside a container:

```bash
nerdctl run --rm --network=none -it \
    --privileged \
    -v /run/k3s/containerd/containerd.sock:/run/containerd/containerd.sock \
    -v /usr/local/bin/nerdctl:/usr/local/bin/nerdctl \
    -v /usr/bin/aa-exec:/usr/bin/aa-exec \
    -v /run/buildkit/buildkitd.sock:/run/buildkit/buildkitd.sock \
    -v /usr/local/bin/buildctl:/usr/local/bin/buildctl \
    -e CONTAINERD_NAMESPACE=k8s.io \
    ubuntu:latest \
    sh -c 'nerdctl ps'
```

## Example Kubernetes Deployment

This is an example kubernetes deployment that will output the results of `nerdctl ps` every 60 seconds:


```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: nerdctl-in-nerdctl
  namespace: default
spec:
  selector:
    matchLabels:
      app: nerdctl-in-nerdctl
  replicas: 1
  strategy:
    rollingUpdate:
      maxSurge: 25%
      maxUnavailable: 25%
    type: RollingUpdate
  template:
    metadata:
      annotations:
        kubectl.kubernetes.io/default-container: nerdctl
      labels:
        app: nerdctl-in-nerdctl
    spec:
      restartPolicy: Always
      containers:
      - name: nerdctl
        image: oliverisaac/alpine-nettools:latest
        command:
        - bash
        - -c
        - while true; do date; nerdctl ps; sleep 60; done
        securityContext:
          privileged: true
        env:
        - name: CONTAINERD_NAMESPACE
          value: k8s.io
        volumeMounts:
        - mountPath: /run/containerd/containerd.sock
          name: containerd-socket
        - mountPath: /usr/local/bin/nerdctl
          name: nerdctl
        - mountPath: /usr/bin/aa-exec
          name: aa-exec
        - mountPath: /run/buildkit/buildkitd.sock
          name: buildkitd-socket
        - mountPath: /usr/local/bin/buildctl
          name: buildctl
      volumes:
        - name: containerd-socket
          hostPath:
            path: /run/k3s/containerd/containerd.sock
            type: Socket
        - name: nerdctl
          hostPath:
            path: /usr/local/bin/nerdctl
            type: File
        - name: aa-exec
          hostPath:
            path: /usr/bin/aa-exec
            type: File
        - name:  buildkitd-socket
          hostPath:
            path: /run/buildkit/buildkitd.sock
            type: Socket
        - name: buildctl
          hostPath:
            path: /usr/local/bin/buildctl
            type: File
```

## Combine with #argo-workflows 

I'll be looking to combine nested containers with argo-workflows to let me build images in my k3s cluster before deploying them. This will let the images be immediately available inside the cluster without needing to pull from remote. It will also help with build times because I won't need to pre-warm the build cache or download cache images on every build.