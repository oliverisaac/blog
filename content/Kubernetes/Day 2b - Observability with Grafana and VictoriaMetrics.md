---
tags:
  - kubernetes
  - grafana
  - victoriametrics
  - observability
---
Now that we've setup our k3s server as documented in [[Day 1a - Setting Up k3s]] and we can configure ingresses after our work in [[Day 2a - Ingress with Nginx and Cert-Manager]], let's start by setting up some observability.

# Why Observability First?

It seems silly that we would set up observability before anything else. However, this discipline will serve us well when the time comes to debug issues and ensure that things are running in a healthy way. This will get us to a place where we can be confident that the server will be able to handle workloads we add and, more importantly, diagnose which service is causing load issues.

If we start collecting metrics now, we'll be able to see trends as we add more services and reconsider choices if we determine they're not scalable. 

## Why [VictoriaMetrics](https://victoriametrics.com/)?

The usual choice for metrics collection and storage on kubernetes is [Prometheus](https://prometheus.io/). However there are competitors to Prometheus that have focused on high-availability, infinite retention , [infinite cost](https://www.google.com/search?q=datadog+high+cost) , or other superlatives. [Thanos](https://thanos.io/) is a good example of one of these competitors. 

That being said, my focus is on running a lightweight stack to squeeze as much performance out of this hardware as possible. In that vein, VictoriaMetrics is an excellent choice. In my experience it uses less memory than Prometheus and can handle many more metrics. It's very performant and is the workhorse I need in a size I can use.

## Why [Grafana](https://grafana.com/)?

Grafana is a free and opensource solution to display metrics collected by VictoriaMetrics. One major benefit of Grafana is that they have a large collection of public dashboards that make it simple to get up and running with graphs without needing to setup your own.

VictoraMetrics has a UI to let you explore graphs, but the flexibility and broad support that grafana gives us is well worth the effort for hosting.

# Installing VictoriaMetrics

VM comes in two different flavors: multi-node and single-server. We do not need the complexity of a multi-node deployment (nor do we have the hardware for it) so we'll be deploying [the single-server helm chart](https://artifacthub.io/packages/helm/victoriametrics/victoria-metrics-single).

The below config is the minimal config I used. If you copy this, ensure that you change the ingress hostname to match your own internal hostname.

Another thing I did is add this to the kubernetes service endpoints:

```yaml
                  # this is custom to oliverisaac
                - source_labels: [ node ]
                  regex: '(.+)'
                  action: replace
                  target_label: instance
```

This was necessary so that when we deploy prometheus node exporter later, the node metrics will be grouped by node name and not by IP address. 


```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: victoriametrics
---
apiVersion: helm.cattle.io/v1
kind: HelmChart
metadata:
  name: victoriametrics
  namespace: victoriametrics
spec:
  repo: https://victoriametrics.github.io/helm-charts/
  chart: victoria-metrics-single
  version: 0.16.0
  targetNamespace: victoriametrics
  valuesContent: |-
    server:
      retentionPeriod: '2w'
      resources:
        requests:
          cpu: 500m
          memory: 512Mi

      ingress:
        # -- Enable deployment of ingress for server component
        enabled: true

        ingressClassName: internal
        pathType: Prefix
        # -- Array of host objects
        hosts:
          - name: victoriametrics.<your internal domain here>
            path:
              - /
            port: http

      # Scrape configuration for victoriametrics
      scrape:
        # -- If true scrapes targets, creates config map or use specified one with scrape targets
        enabled: true
        # -- Scrape config
        config:
          global:
            scrape_interval: 10s

          # Scrape targets
          scrape_configs:
            # Scrape rule for scrape victoriametrics
            - job_name: victoriametrics
              static_configs:
                - targets: [ "localhost:8428" ]

              # COPY from Prometheus helm chart https://github.com/helm/charts/blob/master/stable/prometheus/values.yaml

              # Scrape config for API servers.
              #
              # Kubernetes exposes API servers as endpoints to the default/kubernetes
              # service so this uses `endpoints` role and uses relabelling to only keep
              # the endpoints associated with the default/kubernetes service using the
              # default named port `https`. This works for single API server deployments as
              # well as HA API server deployments.
            - job_name: "kubernetes-apiservers"
              kubernetes_sd_configs:
                - role: endpoints
              # Default to scraping over https. If required, just disable this or change to
              # `http`.
              scheme: https
              # This TLS & bearer token file config is used to connect to the actual scrape
              # endpoints for cluster components. This is separate to discovery auth
              # configuration because discovery & scraping are two separate concerns in
              # Prometheus. The discovery auth config is automatic if Prometheus runs inside
              # the cluster. Otherwise, more config options have to be provided within the
              # <kubernetes_sd_config>.
              tls_config:
                ca_file: /var/run/secrets/kubernetes.io/serviceaccount/ca.crt
                # If your node certificates are self-signed or use a different CA to the
                # master CA, then you need to disable certificate verification. Note that
                # certificate verification is an integral part of a secure infrastructure
                # so this should only be disabled in a controlled environment. You can
                # enable certificate verification by commenting the line below.
                #
                insecure_skip_verify: true
              bearer_token_file: /var/run/secrets/kubernetes.io/serviceaccount/token
              # Keep only the default/kubernetes service endpoints for the https port. This
              # will add targets for each API server which Kubernetes adds an endpoint to
              # the default/kubernetes service.
              relabel_configs:
                - source_labels:
                    [
                        __meta_kubernetes_namespace,
                        __meta_kubernetes_service_name,
                        __meta_kubernetes_endpoint_port_name,
                    ]
                  action: keep
                  regex: default;kubernetes;https
              # Scrape rule using kubernetes service discovery for nodes
            - job_name: "kubernetes-nodes"
              # Default to scraping over https. If required, just disable this or change to
              # `http`.
              scheme: https
              # This TLS & bearer token file config is used to connect to the actual scrape
              # endpoints for cluster components. This is separate to discovery auth
              # configuration because discovery & scraping are two separate concerns in
              # Prometheus. The discovery auth config is automatic if Prometheus runs inside
              # the cluster. Otherwise, more config options have to be provided within the
              # <kubernetes_sd_config>.
              tls_config:
                ca_file: /var/run/secrets/kubernetes.io/serviceaccount/ca.crt
                # If your node certificates are self-signed or use a different CA to the
                # master CA, then you need to disable certificate verification. Note that
                # certificate verification is an integral part of a secure infrastructure
                # so this should only be disabled in a controlled environment. You can
                # enable certificate verification by commenting the line below.
                #
                insecure_skip_verify: true
              bearer_token_file: /var/run/secrets/kubernetes.io/serviceaccount/token
              kubernetes_sd_configs:
                - role: node
              relabel_configs:
                - action: labelmap
                  regex: __meta_kubernetes_node_label_(.+)
                - target_label: __address__
                  replacement: kubernetes.default.svc:443
                - source_labels: [ __meta_kubernetes_node_name ]
                  regex: (.+)
                  target_label: __metrics_path__
                  replacement: /api/v1/nodes/$1/proxy/metrics
              # Scrape rule using kubernetes service discovery for cadvisor
            - job_name: "kubernetes-nodes-cadvisor"
              # Default to scraping over https. If required, just disable this or change to
              # `http`.
              scheme: https
              # This TLS & bearer token file config is used to connect to the actual scrape
              # endpoints for cluster components. This is separate to discovery auth
              # configuration because discovery & scraping are two separate concerns in
              # Prometheus. The discovery auth config is automatic if Prometheus runs inside
              # the cluster. Otherwise, more config options have to be provided within the
              # <kubernetes_sd_config>.
              tls_config:
                ca_file: /var/run/secrets/kubernetes.io/serviceaccount/ca.crt
                # If your node certificates are self-signed or use a different CA to the
                # master CA, then you need to disable certificate verification. Note that
                # certificate verification is an integral part of a secure infrastructure
                # so this should only be disabled in a controlled environment. You can
                # enable certificate verification by commenting the line below.
                #
                insecure_skip_verify: true
              bearer_token_file: /var/run/secrets/kubernetes.io/serviceaccount/token
              kubernetes_sd_configs:
                - role: node
              # This configuration will work only on kubelet 1.7.3+
              # As the scrape endpoints for cAdvisor have changed
              # if you are using older version you need to change the replacement to
              # replacement: /api/v1/nodes/$1:4194/proxy/metrics
              # more info here https://github.com/coreos/prometheus-operator/issues/633
              relabel_configs:
                - action: labelmap
                  regex: __meta_kubernetes_node_label_(.+)
                - target_label: __address__
                  replacement: kubernetes.default.svc:443
                - source_labels: [ __meta_kubernetes_node_name ]
                  regex: (.+)
                  target_label: __metrics_path__
                  replacement: /api/v1/nodes/$1/proxy/metrics/cadvisor
              # ignore timestamps of cadvisor's metrics by default
              # more info here https://github.com/VictoriaMetrics/VictoriaMetrics/issues/4697#issuecomment-1656540535
              honor_timestamps: false 
            # Scrape config for service endpoints.
            #
            # The relabeling allows the actual service scrape endpoint to be configured
            # via the following annotations:
            #
            # * `prometheus.io/scrape`: Only scrape services that have a value of `true`
            # * `prometheus.io/scheme`: If the metrics endpoint is secured then you will need
            # to set this to `https` & most likely set the `tls_config` of the scrape config.
            # * `prometheus.io/path`: If the metrics path is not `/metrics` override this.
            # * `prometheus.io/port`: If the metrics are exposed on a different port to the
            # service then set this appropriately.
            #
            # Scrape rule using kubernetes service discovery for endpoints
            - job_name: "kubernetes-service-endpoints"
              kubernetes_sd_configs:
                - role: endpoints
              relabel_configs:
                - action: drop
                  source_labels: [ __meta_kubernetes_pod_container_init ]
                  regex: true
                - action: keep_if_equal
                  source_labels: [ __meta_kubernetes_service_annotation_prometheus_io_port, __meta_kubernetes_pod_container_port_number ]
                - source_labels:
                    - __meta_kubernetes_service_annotation_prometheus_io_scrape
                  action: keep
                  regex: true
                - source_labels:
                    [ __meta_kubernetes_service_annotation_prometheus_io_scheme ]
                  action: replace
                  target_label: __scheme__
                  regex: (https?)
                - source_labels:
                    [ __meta_kubernetes_service_annotation_prometheus_io_path ]
                  action: replace
                  target_label: __metrics_path__
                  regex: (.+)
                - source_labels:
                    [
                        __address__,
                        __meta_kubernetes_service_annotation_prometheus_io_port,
                    ]
                  action: replace
                  target_label: __address__
                  regex: ([^:]+)(?::\d+)?;(\d+)
                  replacement: $1:$2
                - action: labelmap
                  regex: __meta_kubernetes_service_label_(.+)
                - source_labels: [ __meta_kubernetes_namespace ]
                  action: replace
                  target_label: namespace
                - source_labels: [ __meta_kubernetes_service_name ]
                  action: replace
                  target_label: service
                - source_labels: [ __meta_kubernetes_pod_node_name ]
                  action: replace
                  target_label: node
                  
                  # this is custom to oliverisaac
                - source_labels: [ node ]
                  regex: '(.+)'
                  action: replace
                  target_label: instance
            # Scrape config for slow service endpoints; same as above, but with a larger
            # timeout and a larger interval
            #
            # The relabeling allows the actual service scrape endpoint to be configured
            # via the following annotations:
            #
            # * `prometheus.io/scrape-slow`: Only scrape services that have a value of `true`
            # * `prometheus.io/scheme`: If the metrics endpoint is secured then you will need
            # to set this to `https` & most likely set the `tls_config` of the scrape config.
            # * `prometheus.io/path`: If the metrics path is not `/metrics` override this.
            # * `prometheus.io/port`: If the metrics are exposed on a different port to the
            # service then set this appropriately.
            #
            - job_name: "kubernetes-service-endpoints-slow"
              scrape_interval: 5m
              scrape_timeout: 30s
              kubernetes_sd_configs:
                - role: endpoints
              relabel_configs:
                - action: drop
                  source_labels: [ __meta_kubernetes_pod_container_init ]
                  regex: true
                - action: keep_if_equal
                  source_labels: [ __meta_kubernetes_service_annotation_prometheus_io_port, __meta_kubernetes_pod_container_port_number ]
                - source_labels:
                    [ __meta_kubernetes_service_annotation_prometheus_io_scrape_slow ]
                  action: keep
                  regex: true
                - source_labels:
                    [ __meta_kubernetes_service_annotation_prometheus_io_scheme ]
                  action: replace
                  target_label: __scheme__
                  regex: (https?)
                - source_labels:
                    [ __meta_kubernetes_service_annotation_prometheus_io_path ]
                  action: replace
                  target_label: __metrics_path__
                  regex: (.+)
                - source_labels:
                    [
                        __address__,
                        __meta_kubernetes_service_annotation_prometheus_io_port,
                    ]
                  action: replace
                  target_label: __address__
                  regex: ([^:]+)(?::\d+)?;(\d+)
                  replacement: $1:$2
                - action: labelmap
                  regex: __meta_kubernetes_service_label_(.+)
                - source_labels: [ __meta_kubernetes_namespace ]
                  action: replace
                  target_label: namespace
                - source_labels: [ __meta_kubernetes_service_name ]
                  action: replace
                  target_label: service
                - source_labels: [ __meta_kubernetes_pod_node_name ]
                  action: replace
                  target_label: node
                - source_labels: [ node ]
                  regex: '(.+)'
                  action: replace
                  target_label: instance
            # Example scrape config for probing services via the Blackbox Exporter.
            #
            # The relabeling allows the actual service scrape endpoint to be configured
            # via the following annotations:
            #
            # * `prometheus.io/probe`: Only probe services that have a value of `true`
            #
            - job_name: "kubernetes-services"
              metrics_path: /probe
              params:
                module: [ http_2xx ]
              kubernetes_sd_configs:
                - role: service
              relabel_configs:
                - source_labels:
                    - __meta_kubernetes_service_annotation_prometheus_io_probe
                  action: keep
                  regex: true
                - source_labels: [ __address__ ]
                  target_label: __param_target
                - target_label: __address__
                  replacement: blackbox
                - source_labels: [ __param_target ]
                  target_label: instance
                - action: labelmap
                  regex: __meta_kubernetes_service_label_(.+)
                - source_labels: [ __meta_kubernetes_namespace ]
                  target_label: namespace
                - source_labels: [ __meta_kubernetes_service_name ]
                  target_label: service
            # Example scrape config for pods
            #
            # The relabeling allows the actual pod scrape endpoint to be configured via the
            # following annotations:
            #
            # * `prometheus.io/scrape`: Only scrape pods that have a value of `true`
            # * `prometheus.io/path`: If the metrics path is not `/metrics` override this.
            # * `prometheus.io/port`: Scrape the pod on the indicated port instead of the default of `9102`.
            #
            - job_name: "kubernetes-pods"
              kubernetes_sd_configs:
                - role: pod
              relabel_configs:
                - action: drop
                  source_labels: [ __meta_kubernetes_pod_container_init ]
                  regex: true
                - action: keep_if_equal
                  source_labels: [ __meta_kubernetes_pod_annotation_prometheus_io_port, __meta_kubernetes_pod_container_port_number ]
                - source_labels: [ __meta_kubernetes_pod_annotation_prometheus_io_scrape ]
                  action: keep
                  regex: true
                - source_labels: [ __meta_kubernetes_pod_annotation_prometheus_io_path ]
                  action: replace
                  target_label: __metrics_path__
                  regex: (.+)
                - source_labels:
                    [ __address__, __meta_kubernetes_pod_annotation_prometheus_io_port ]
                  action: replace
                  regex: ([^:]+)(?::\d+)?;(\d+)
                  replacement: $1:$2
                  target_label: __address__
                - action: labelmap
                  regex: __meta_kubernetes_pod_label_(.+)
                - source_labels: [ __meta_kubernetes_namespace ]
                  action: replace
                  target_label: namespace
                - source_labels: [ __meta_kubernetes_pod_name ]
                  action: replace
                  target_label: pod
              # End of COPY

```

# Installing Node Exporter

Speaking of node-exporter, we also want to install the [Prometheus node exporter](https://artifacthub.io/packages/helm/prometheus-community/prometheus-node-exporter) so that we can have metrics about our host. When we combine this with Grafana later, we'll get nice graphs like these:

![[Screenshot 2025-04-05 at 10.31.37 PM.png|Lovely graphs in grafana showing the health of our k3s node]]


This helm chart is much simpler than the previous one! Note that we need to add an annotation to the scrape config so that VictoriaMetrics will be able to discover how to scrape the node exporters.

```yaml
apiVersion: helm.cattle.io/v1
kind: HelmChart
metadata:
  name: prometheus-node-exporter
  namespace: victoriametrics
spec:
  repo: https://prometheus-community.github.io/helm-charts
  chart: prometheus-node-exporter
  version: 4.45.0
  targetNamespace: victoriametrics
  valuesContent: |-
    nameOverride: "prometheus-node-exporter"
    fullnameOverride: "prometheus-node-exporter"

    ## Service configuration
    service:
      ## Additional annotations and labels for the service
      annotations:
        prometheus.io/scrape: "true"
        prometheus.io/port: "9100"
```

# Installing Grafana

Now we're finally getting to the good stuff! Grafana is pretty straight-forward to deploy with the exception that we'll need to add another secret to set up auth:

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: grafana-admin
  namespace: grafana
type: Opaque
stringData:
  admin-user: "admin"
  admin-password: "YOUR PASSWORD GOES HERE"
```

With that deployed, we can then set up the grafana helm chart. This minimal config will deploy with several dashboards already pre-populated as well as the VictoriaMetrics datasource already setup. 

Later on we'll be setting up postfix to allow us to send emails ( [[Day 3c - Egress with Postfix]]), so I left that config in this helm chart but disabled emails for now.

Make sure you tweak the ingress hostname.

```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: grafana
---
apiVersion: helm.cattle.io/v1
kind: HelmChart
metadata:
  name: 'grafana'
  namespace: grafana
spec:
  repo: 'https://grafana.github.io/helm-charts'
  chart: 'grafana'
  version: '8.11.0'
  targetNamespace: 'grafana'
  valuesContent: |-
    serviceAccount:
      create: true
      name: grafana

    ingress:
      enabled: true
      ingressClassName: internal
      hosts:
        - grafana.<your internal domain here> # TODO: change this

    ## Enable persistence using Persistent Volume Claims
    ## ref: https://kubernetes.io/docs/user-guide/persistent-volumes/
    ##
    persistence:
      type: pvc
      enabled: true
      accessModes:
        - ReadWriteOnce
      size: 2Gi
      finalizers:
        - kubernetes.io/pvc-protection

      ## If 'lookupVolumeName' is set to true, Helm will attempt to retrieve
      ## the current value of 'spec.volumeName' and incorporate it into the template.
      lookupVolumeName: false

    # Use an existing secret for the admin user.
    admin:
      ## Name of the secret. Can be templated.
      existingSecret: "grafana-admin"
      userKey: admin-user
      passwordKey: admin-password

    ## Configure grafana datasources
    ## ref: http://docs.grafana.org/administration/provisioning/#datasources
    ##
    datasources: 
      datasources.yaml:
        apiVersion: 1
        datasources:
        - name: VictoriaMetrics
          type: prometheus
          url: 'http://victoriametrics-victoria-metrics-single-server.victoriametrics.svc.cluster.local:8428'
          access: proxy
          isDefault: true
        deleteDatasources: []


    ## Configure grafana dashboard providers
    ## ref: http://docs.grafana.org/administration/provisioning/#dashboards
    ##
    ## `path` must be /var/lib/grafana/dashboards/<provider_name>
    ##
    dashboardProviders: 
      dashboardproviders.yaml:
        apiVersion: 1
        providers:
        - name: 'default'
          orgId: 1
          folder: ''
          type: file
          disableDeletion: false
          editable: true
          options:
            path: /var/lib/grafana/dashboards/default

    ## Configure grafana dashboard to import
    ## NOTE: To use dashboards you must also enable/configure dashboardProviders
    ## ref: https://grafana.com/dashboards
    ##
    ## dashboards per provider, use provider name as key.
    ##
    dashboards:
      default:
        victoriametrics:
          gnetId: 10229
          revision: 38
          datasource: VictoriaMetrics
        k3s-cluster:
          gnetId: 15282
          revision: 1
          datasource: VictoriaMetrics
        postfix:
          gnetId: 10013
          revision: 2
          datasource: VictoriaMetrics
        node-exporter:
          gnetId: 1860
          revision: 37
          datasource: VictoriaMetrics


    ## Grafana's primary configuration
    ## NOTE: values in map will be converted to ini format
    ## ref: http://docs.grafana.org/installation/configuration/
    ##
    grafana.ini:
      paths:
        data: /var/lib/grafana/
        logs: /var/log/grafana
        plugins: /var/lib/grafana/plugins
        provisioning: /etc/grafana/provisioning
      analytics:
        check_for_updates: true
      log:
        mode: console
      grafana_net:
        url: https://grafana.net
      smtp:
        enabled: false
        from_address: "youremail.example.com"
        from_name: Grafana
        host: mail.mail:25
        skip_verify: "true"

    ## Add a seperate remote image renderer deployment/service
    imageRenderer:
      # Enable the image-renderer deployment & service
      enabled: true
      replicas: 1
      autoscaling:
        enabled: false

```

# Observability done!

Now that we have VictoriaMetrics, prometheus node-exporter, and Grafana deployed, we have the very start of our observability stack! We can see if our node is healthy and look back at historical trends to make sure we're not blowing up the hardware.

As you deploy these helm charts it's useful to read through the entire values.yaml that is available to you because there might be features available in there that you aren't aware of. For example, Grafana supports OpenID or LDAP auth, but I removed those options (for now!) from my config.

## A Problem Discovered

My emphasis on getting observability deployed first ended up paying off big-time when I first got my graphs running. I discovered I was quickly running out of disk!

![[Blog/Published/images/Screenshot 2025-04-05 at 11.03.42 PM.png]]5 at 11.03.42 PM.png]]

Within 48 hours of booting this host my `/var` partition is nearly 60% full?! What has gone wrong?! 

Well, it turns out the answer was simple: when I originally installed the OS I went with the suggested partitioning scheme. This scheme put hardly any space towards `/var` and the majority of the space towards `/home`! 

In the next post, we'll explore how I was able to fix this partitioning issue without needing to reinstall the entire OS: [[Day 3a - Fixing Partitioning Problems]]
