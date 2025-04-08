> [!note]
> This post is part of my [[7 Days Of Kubernetes]] where I explore setting up [a cheap MiniPC](https://amzn.to/42tenCq) as a single-node Kubernetes cluster using k3s.

Yesterday we [[Day 2b - Observability with Grafana and VictoriaMetrics|set up Grafana and VictoriaMetrics]] but there's no way for us to get alerted if there are emergent issues. To solve this, today we're going to add support for sending emails using postfix to proxy through gmail.

> [!warning] Don't Send Email People Didn't Ask For
> Look, I shouldn't have to say this: don't send emails to people who didn't explicitly ask to get emails from you. It's illegal and immoral. Plus gmail will block you. 

# Setup a Gmail Account

The first step is to setup a new Gmail account. I wanted my server to have a different email from my primary so that emails coming from it would have a unique identity. 

## Setup Two-Factor Auth

In order to use the postfix proxy you will need an "app password" to send email. To get this, you first setup two-factor auth. Then [go to the two-factor auth settings page](myaccount.google.com/signinoptions/twosv) and scroll to the bottom where you can select to manage app passwords:

![[Screenshot 2025-04-07 at 10.04.21 PM.png]]

# Setup the mail secret

Now we need to setup a new secret to hold the password. They syntax should look like this:

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: postfix-config
  namespace: mail
type: Opaque
stringData:
  RELAYHOST: "[smtp.gmail.com]:587"
  ALLOWED_SENDER_DOMAINS: "gmail.com"
  RELAYHOST_USERNAME: <YOUR EMAIL ADDRESS>@gmail.com
  RELAYHOST_PASSWORD: <YOUR APP PASSWORD>
```

Make sure to edit the username and password fields with your email and password.

# Deploy the Helm Chart

Now that we have our secret configured, we can deploy [the docker-postfix helm chart](https://artifacthub.io/packages/helm/docker-postfix/mail):

```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: mail
---
apiVersion: helm.cattle.io/v1
kind: HelmChart
metadata:
  name: mail
  namespace: mail
spec:
  repo: https://bokysan.github.io/docker-postfix/
  chart: mail
  version: 4.4.0
  targetNamespace: mail
  valuesContent: |-
    # Do a name override so we send mail using: `mail.mail``
    nameOverride: "mail"
    fullnameOverride: "mail"

    # Send using port 25 so there is no TLS required
    service:
      port: 25 
      type: ClusterIP

    # Enable metrics
    metrics:
      enabled: true
      port: 9154
      path: /metrics
      service:
        annotations: 
          prometheus.io/scrape: "true"
          prometheus.io/port: "9154"

```

The big changes we make to the default values are switching to port 25 and using a `nameOverride` so that the service will be named `mail`. This means we can send mail using `mail.mail:25` which is pretty easy to remember!

# Test the Result

Now we can test it out! Use `kubectl exec` to hop into the mail pod:

```bash
kubectl -n mail exec -it mail-0 -c mail -- bash -o vi
```

Once you're inside the container, try sending an email:

```bash
sendmail person-to-send-email-to@example.com <<EOEMAIL
Subject: This is the subject line

This is the body

Which has multiple lines

EOEMAIL
```

Make sure to edit the destination email address to yourself and the email should show up in your inbox!

![[Screenshot 2025-04-07 at 10.25.43 PM.png]]

# Reconfigure Grafana

Now that we have our mail server we can configure Grafana to use it!

In your helm chart that deploys grafana, find the `grafana.ini` key and ensure the smtp section is correctly configured:

```yaml
grafana.ini:
    [... snip ...]
    smtp:
        enabled: true
        from_address: "youremail@example.com"
        from_name: Grafana
        host: mail.mail:25
        skip_verify: "true"
```

Commit those changes and redeploy them.
## Test Grafana Email Sending

Now you can login to your grafana instance and navigate to `Contact Points` under `Alerting`:

![[Screenshot 2025-04-07 at 10.35.15 PM.png]]

Edit the `grafana-default-email` contact point with your desired email address and send a test email. If all goes well you should get an email in your inbox!

![[Screenshot 2025-04-07 at 10.39.10 PM.png]]

# Next Steps

Now that we have our observability rolled out, we can start deploying bigger services. The first of which is going to be argo-cd. Follow along in [[Day 4a - Configure ArgoCD]]!