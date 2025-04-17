> [!note]
> This post is part of my [[7 Days Of Kubernetes]] where I explore setting up [a cheap MiniPC](https://amzn.to/42tenCq) as a single-node Kubernetes cluster using k3s.

Now that we [setup argo workflows]([[Day 5 - Deploying Argo Workflows]]), we want to see about creating a workflow to build docker images.

# Start with the Basics

To get started, we'll build a Workflow that can build a docker image from a hardcoded file. This gives us a baseline to build from:

```yaml
apiVersion: argoproj.io/v1alpha1
kind: WorkflowTemplate
metadata:
  name: docker-build
  namespace: argo-workflow-jobs
spec:
  entrypoint: pipeline

  # Create a volume to hold our source code
  volumeClaimTemplates:
    - metadata:
        name: repo-root
      spec:
        accessModes: ["ReadWriteOnce"]
        resources:
          requests:
            storage: 1Gi

  #mount secrets for the workflow
  volumes:
    - name: dockerhub-creds
      secret:
        defaultMode: 0444
        secretName: dockerhub-creds

  #start the sequence
  templates:
    - name: pipeline
      steps:
        - - name: generate-dockerfile
            template: generate-dockerfile
        - - name: build-docker
            template: build-docker

    - name: generate-dockerfile
      container:
        image: oliverisaac/alpine-nettools:latest
        command:
          - "bash"
          - "-c"
          - |
            set -eEuo pipefail

            # Create a very basic dockerfile
            cat > /workdir/Dockerfile <<EODOCKER
            FROM alpine:latest
            RUN uname -a > /uname.out
            ENTRYPOINT [ "cat", "/uname.out" ]

            EODOCKER
        volumeMounts:
          - name: repo-root
            mountPath: /workdir

    - name: build-docker
      container:
        #argo is gonna ask for a command - the debug version allows us to exec this way i think
        image: gcr.io/kaniko-project/executor:v1.23.2-debug
        imagePullPolicy: IfNotPresent
        command: ["/kaniko/executor"]
        args:
          - "--dockerfile=Dockerfile"
          - "--context=/workdir"
          - "--destination=oliverisaac/test-kaniko:latest"
        volumeMounts:
          - name: dockerhub-creds
            mountPath: /kaniko/.docker/
          - name: repo-root
            mountPath: /workdir
        resources:
          limits:
            cpu: 4
            memory: 2Gi
```

This is a workflow template which writes a pretty unexciting Dockerfile to a shared volume then uses Kaniko to build a container using that Dockerfile. After building the image, Kaniko pushes to dockerhub using some dockerhub credentials we included.


> [!tip] Update the Push Target
> Make sure to update the `--destination` flag in the above example so that it gets pushed to your dockerhub account!



## Creating the dockerhub credentials

The dockerhub credentials secret should look something like this:

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: dockerhub-creds
  namespace: argo-workflow-jobs
stringData:
  config.json: |
    {
      "auths": {
        "https://index.docker.io/v1/": {
          "auth": "<base64 encoded usernmae:token>"
        }
      }
    }
```

To create the auth value, get a token form dockerhub which is allowed to push images. Then use the below example shell command to generate the base64 encoded value:

```bash
printf "%s:%s" "USERNAME" "TOKEN" | base64 | tr -d '\n'
```

It is important there is not a trailing newline in the colon-joined username/password before it is base64 encoded.

# Cloning From Github

Now that we have the basics of using Kaniko set up, let's focus on pulling down the git repo during the build.

## Setup github creds

First, generate a new SSH key to be used by your clients:

```bash
ssh-keygen -t rsa -b 4096 -C "argo-workflows" -f /tmp/argo-workflows.id_rsa
```

Then you can create a new kubernetes secrets with the `known_hosts` file as well as the private key:

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: github-creds
  namespace: argo-workflow-jobs
stringData:
  id_rsa: |
    -----BEGIN OPENSSH PRIVATE KEY-----
    woierjweoirjweoirjweoirjweoirjweoirjweoijroiwjroiwe
    wworijweoirjweorijweoirjwodsnnsdfoweijroiwejrwwoeri
    weoirjweoirjweoirjweoirjwoeirjwoeirjweoirjwoeij==
    -----END OPENSSH PRIVATE KEY-----

  known_hosts: |
    github.com ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQCj7ndNxQowgcQnjshcLrqPEiiphnt+VTTvDP6mHBL9j1aNUkY4Ue1gvwnGLVlOhGeYrnZaMgRK6+PKCUXaDbC7qtbW8gIkhL7aGCsOr/C56SJMy/BCZfxd1nWzAOxSDPgVsmerOBYfNqltV9/hWCqBywINIR+5dIg6JTJ72pcEpEjcYgXkE2YEFXV1JHnsKgbLWNlhScqb2UmyRkQyytRLtL+38TGxkxCflmO+5Z8CSSNY7GidjMIZ7Q4zMjA2n1nGrlTDkzwDCsw+wqFPGQA179cnfGWOWRVruj16z6XyvxvjJwbz0wQZ75XK5tKSb7FNyeIEs4TT4jk+S4dhPeAUC5y+bDYirYgM4GC7uEnztnZyaVWQ7B381AK4Qdrwt51ZqExKbQpTUNn+EjqoTwvqNj4kqx5QUCI0ThS/YkOxJCXmPUWZbhjpCg56i+2aB6CmK2JGhn57K5mj0MNdBXA4/WnwH6XoPWJzK5Nyu2zB3nAZp+S5hpQs+p1vN1/wsjk=
    github.com ecdsa-sha2-nistp256 AAAAE2VjZHNhLXNoYTItbmlzdHAyNTYAAAAIbmlzdHAyNTYAAABBBEmKSENjQEezOmxkZMy7opKgwFB9nkt5YRrYMjNuG5N87uRgg6CLrbo5wAdT/y6v0mKV0U2w0WZ2YB/++Tpockg=
    github.com ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOMqqnkVzrm0SdG6UOoqKLsabgH5C9okWi0dh2l9GKJl

```

Then log into your github account and add the `/tmp/argo-workflows.id_rsa.pub` public key to your account.

## Use the Creds In the Workflow

Now we can update our `generate-dockerfile` template so that it clones from git using those credentials:

```yaml
spec:
    volumes:
    # Add this volume:
    - name: github-creds
      secret:
        defaultMode: 0400
        secretName: github-creds
        
    templates:
    # Update this template
    - name: generate-dockerfile
      container:
        image: oliverisaac/alpine-nettools:latest
        command:
          - "bash"
          - "-c"
          - |
            set -eEuo pipefail
            git clone "git@github.com:oliverisaac/alpine-nettools.git" /workdir/.
        volumeMounts:
          - name: repo-root
            mountPath: /workdir
          - name: github-creds
            mountPath: /root/.ssh/        
```

Great! Now we're building from a github repo! But the repo is static, let's setup a parameter so things are a bit more dynamic...

# Adding Parameters

We can add arguments to our top-level workflow and then consume them in later steps.

```yaml
spec:
  arguments:
    parameters:
      - name: repo
        value: "git@github.com:oliverisaac/alpine-nettools.git"
```

Now we update our `generate-dockerfile` to pull using that parameter. To help with quoting, we'll pass the parameter using an environment variable:

```yaml
spec:
    templates:
    # Update this template
    - name: generate-dockerfile
      container:
        image: oliverisaac/alpine-nettools:latest
        env:
        - name: REPO
          value: "{{workflow.parameters.repo}}"
        command:
          - "bash"
          - "-c"
          - |
            set -eEuo pipefail
            git clone "$REPO" /workdir/.

```

Now when you go to run the workflow you'll be prompted with the option to put in a different repo:

![[Screenshot 2025-04-16 at 9.16.11 PM.png]]

# Adding Dynamic Parameters

Another thing we can do is adding parameters to later steps that are created in earlier steps. 

For example, what if we want Kaniko to tag the image with the git hash of the commit we cloned down?

We can do this by writing values to files then marking those files as "outputs" in the workflow template.

## Generate the outputs:

Update your `generate-dockerfile` step so that it outputs the git hash of the current commit:

```yaml
spec:
    templates:
    - name: generate-dockerfile
      container:
        image: oliverisaac/alpine-nettools:latest
        env:
        - name: REPO
          value: "{{workflow.parameters.repo}}"
        command:
          - "bash"
          - "-c"
          - |
            set -eEuo pipefail
            cd /workdir/.

            git clone "$REPO" .
            # Generate the output value
            git rev-parse --short HEAD > /tmp/image_tag
        volumeMounts:
          - name: repo-root
            mountPath: /workdir
          - name: github-creds
            mountPath: /root/.ssh/
      # Add the outputs
      outputs:
        parameters:
        - name: image_tag
          valueFrom:
            path: /tmp/image_tag
```

## Add inputs to your kaniko build step

We now update our `build-docker` step to have an input parameter of `input_tag` and add an additional `--destination` argument which uses that parameter:

```yaml
spec:
  templates:
    - name: build-docker
      inputs:
        parameters:
          - name: image_tag

      container:
        image: gcr.io/kaniko-project/executor:v1.23.2-debug
        imagePullPolicy: IfNotPresent
        command: ["/kaniko/executor"]
        args:
          - "--dockerfile=Dockerfile"
          - "--context=/workdir"
          - "--destination=oliverisaac/test-kaniko:latest"
          - "--destination=oliverisaac/test-kaniko:{{inputs.parameters.image_tag}}"
```

## Hook together the outputs and inputs

As a final step, we need to tell argo how to hook up these outputs and inputs. You do this in the `pipeline` template:

```yaml
spec:
  templates:
    - name: pipeline
      steps:
        - - name: generate-dockerfile
            template: generate-dockerfile
        - - name: build-docker
            template: build-docker
            arguments:
              parameters:
              - name: "image_tag"
                value: "{{steps.generate-dockerfile.outputs.parameters.image_tag}}"
```

## Testing it out

You can now run your pipeline and you should get a dynamically tagged image! If you click on the `build-docker` step and select the `inputs/outputs` section you can see that the git hash is indeed being passed in:

![[Screenshot 2025-04-16 at 9.29.55 PM.png]]

# Final Product

The final pipeline looks like this:

```yaml
apiVersion: argoproj.io/v1alpha1
kind: WorkflowTemplate
metadata:
  name: docker-build
  namespace: argo-workflow-jobs
spec:
  entrypoint: pipeline

  arguments:
    parameters:
      - name: repo
        value: "git@github.com:oliverisaac/alpine-nettools.git"

  # Create a volume to hold our source code
  volumeClaimTemplates:
    - metadata:
        name: repo-root
      spec:
        accessModes: ["ReadWriteOnce"]
        resources:
          requests:
            storage: 1Gi

  #mount secrets for the workflow
  volumes:
    - name: dockerhub-creds
      secret:
        defaultMode: 0444
        secretName: dockerhub-creds
    - name: github-creds
      secret:
        defaultMode: 0400
        secretName: github-creds

  #start the sequence
  templates:
    - name: pipeline
      steps:
        - - name: generate-dockerfile
            template: generate-dockerfile
        - - name: build-docker
            template: build-docker
            arguments:
              parameters:
              - name: "image_tag"
                value: "{{steps.generate-dockerfile.outputs.parameters.image_tag}}"

    - name: generate-dockerfile
      container:
        image: oliverisaac/alpine-nettools:latest
        env:
        - name: REPO
          value: "{{workflow.parameters.repo}}"
        command:
          - "bash"
          - "-c"
          - |
            set -eEuo pipefail
            cd /workdir/.

            git clone "$REPO" .
            git rev-parse --short HEAD > /tmp/image_tag
        volumeMounts:
          - name: repo-root
            mountPath: /workdir
          - name: github-creds
            mountPath: /root/.ssh/
      outputs:
        parameters:
        - name: image_tag
          valueFrom:
            path: /tmp/image_tag

    - name: build-docker
      inputs:
        parameters:
        - name: image_tag
      container:
        #argo is gonna ask for a command - the debug version allows us to exec this way i think
        image: gcr.io/kaniko-project/executor:v1.23.2-debug
        imagePullPolicy: IfNotPresent
        command: ["/kaniko/executor"]
        args:
          - "--dockerfile=Dockerfile"
          - "--context=/workdir"
          - "--destination=oliverisaac/test-kaniko:latest"
          - "--destination=oliverisaac/test-kaniko:{{inputs.parameters.image_tag}}"
        volumeMounts:
          - name: dockerhub-creds
            mountPath: /kaniko/.docker/
          - name: repo-root
            mountPath: /workdir
        resources:
          limits:
            cpu: 4
            memory: 2Gi
```

You can continue to mess around with the pipeline and tweak it to your heart's content!

My final pipeline ended up being quite a bit more complicated with parameters for Dockerfile path and branch name as well as setting up caching using kaniko's pre-warmed cache as well as caching layers stored in dockerhub. To learn more about that, check out the final post in this series! [[Day 7 - Connecting GitHub Webhook to Argo Workflows To Trigger Builds]]