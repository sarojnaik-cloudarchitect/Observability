# Observability
Observability-multicloud-AWSLandingzone
User: step by step aws landing zone observability platform for multicloud data extraction from eks,gke,aks.If possbile convert it as pdf.Observabilty platform should use opentelemetry(otel) and newrelics
Model: # Multi-Cloud Observability Platform with OpenTelemetry and New Relic

## Complete Step-by-Step Implementation Guide

---

## Table of Contents

1. [Architecture Overview](#architecture-overview)
2. [Prerequisites](#prerequisites)
3. [AWS Landing Zone Setup](#aws-landing-zone-setup)
4. [OpenTelemetry Collector Deployment](#opentelemetry-collector-deployment)
5. [EKS Integration](#eks-integration)
6. [GKE Integration](#gke-integration)
7. [AKS Integration](#aks-integration)
8. [New Relic Configuration](#new-relic-configuration)
9. [Monitoring & Alerting](#monitoring-alerting)
10. [Best Practices](#best-practices)

---

## 1. Architecture Overview

### High-Level Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    AWS Landing Zone (Hub)                    │
│  ┌──────────────────────────────────────────────────────┐  │
│  │              Central Observability VPC                │  │
│  │  ┌────────────────────────────────────────────────┐  │  │
│  │  │      OpenTelemetry Collector (Gateway)         │  │  │
│  │  │  - Metrics Processing                          │  │  │
│  │  │  - Traces Processing                           │  │  │
│  │  │  - Logs Processing                             │  │  │
│  │  └────────────────────────────────────────────────┘  │  │
│  │                        ↓                              │  │
│  │  ┌────────────────────────────────────────────────┐  │  │
│  │  │           New Relic Platform                   │  │  │
│  │  └────────────────────────────────────────────────┘  │  │
│  └──────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────┘
              ↑                ↑                ↑
              │                │                │
        ┌─────┴────┐     ┌────┴─────┐    ┌────┴─────┐
        │   EKS    │     │   GKE    │    │   AKS    │
        │  (AWS)   │     │ (Google) │    │ (Azure)  │
        └──────────┘     └──────────┘    └──────────┘
```

---

## 2. Prerequisites

### Required Tools

```bash
# Install required CLI tools

# AWS CLI
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip awscliv2.zip
sudo ./aws/install

# kubectl
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
chmod +x kubectl
sudo mv kubectl /usr/local/bin/

# Helm
curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

# eksctl
curl --silent --location "https://github.com/weaveworks/eksctl/releases/latest/download/eksctl_$(uname -s)_amd64.tar.gz" | tar xz -C /tmp
sudo mv /tmp/eksctl /usr/local/bin

# gcloud CLI
curl https://sdk.cloud.google.com | bash
exec -l $SHELL
gcloud init

# Azure CLI
curl -sL https://aka.ms/InstallAzureCLIDeb | sudo bash

# Terraform
wget https://releases.hashicorp.com/terraform/1.6.0/terraform_1.6.0_linux_amd64.zip
unzip terraform_1.6.0_linux_amd64.zip
sudo mv terraform /usr/local/bin/
```

### Required Accounts & Credentials

- AWS Account with Admin access
- GCP Project with Owner access
- Azure Subscription with Contributor access
- New Relic Account (Free or Paid tier)

---

## 3. AWS Landing Zone Setup

### Step 3.1: Create Landing Zone Infrastructure

Create a file: `terraform/landing-zone/main.tf`

```hcl
# terraform/landing-zone/main.tf

terraform {
  required_version = ">= 1.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

# VPC for Observability Platform
resource "aws_vpc" "observability_vpc" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name        = "observability-vpc"
    Environment = var.environment
    Purpose     = "central-observability"
  }
}

# Public Subnets
resource "aws_subnet" "public_subnets" {
  count                   = 3
  vpc_id                  = aws_vpc.observability_vpc.id
  cidr_block              = "10.0.${count.index + 1}.0/24"
  availability_zone       = data.aws_availability_zones.available.names[count.index]
  map_public_ip_on_launch = true

  tags = {
    Name = "observability-public-subnet-${count.index + 1}"
    Type = "public"
  }
}

# Private Subnets
resource "aws_subnet" "private_subnets" {
  count             = 3
  vpc_id            = aws_vpc.observability_vpc.id
  cidr_block        = "10.0.${count.index + 10}.0/24"
  availability_zone = data.aws_availability_zones.available.names[count.index]

  tags = {
    Name = "observability-private-subnet-${count.index + 1}"
    Type = "private"
  }
}

# Internet Gateway
resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.observability_vpc.id

  tags = {
    Name = "observability-igw"
  }
}

# NAT Gateways
resource "aws_eip" "nat_eips" {
  count  = 3
  domain = "vpc"

  tags = {
    Name = "observability-nat-eip-${count.index + 1}"
  }
}

resource "aws_nat_gateway" "nat_gateways" {
  count         = 3
  allocation_id = aws_eip.nat_eips[count.index].id
  subnet_id     = aws_subnet.public_subnets[count.index].id

  tags = {
    Name = "observability-nat-${count.index + 1}"
  }

  depends_on = [aws_internet_gateway.igw]
}

# Route Tables
resource "aws_route_table" "public_rt" {
  vpc_id = aws_vpc.observability_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }

  tags = {
    Name = "observability-public-rt"
  }
}

resource "aws_route_table" "private_rt" {
  count  = 3
  vpc_id = aws_vpc.observability_vpc.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.nat_gateways[count.index].id
  }

  tags = {
    Name = "observability-private-rt-${count.index + 1}"
  }
}

# Route Table Associations
resource "aws_route_table_association" "public_rta" {
  count          = 3
  subnet_id      = aws_subnet.public_subnets[count.index].id
  route_table_id = aws_route_table.public_rt.id
}

resource "aws_route_table_association" "private_rta" {
  count          = 3
  subnet_id      = aws_subnet.private_subnets[count.index].id
  route_table_id = aws_route_table.private_rt[count.index].id
}

# Security Group for OTel Collector
resource "aws_security_group" "otel_collector_sg" {
  name        = "otel-collector-sg"
  description = "Security group for OpenTelemetry Collector"
  vpc_id      = aws_vpc.observability_vpc.id

  # OTLP gRPC
  ingress {
    from_port   = 4317
    to_port     = 4317
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "OTLP gRPC receiver"
  }

  # OTLP HTTP
  ingress {
    from_port   = 4318
    to_port     = 4318
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "OTLP HTTP receiver"
  }

  # Prometheus metrics
  ingress {
    from_port   = 8888
    to_port     = 8888
    protocol    = "tcp"
    cidr_blocks = ["10.0.0.0/16"]
    description = "Prometheus metrics"
  }

  # Health check
  ingress {
    from_port   = 13133
    to_port     = 13133
    protocol    = "tcp"
    cidr_blocks = ["10.0.0.0/16"]
    description = "Health check"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "otel-collector-sg"
  }
}

# Data source for availability zones
data "aws_availability_zones" "available" {
  state = "available"
}

# Outputs
output "vpc_id" {
  value = aws_vpc.observability_vpc.id
}

output "public_subnet_ids" {
  value = aws_subnet.public_subnets[*].id
}

output "private_subnet_ids" {
  value = aws_subnet.private_subnets[*].id
}

output "otel_security_group_id" {
  value = aws_security_group.otel_collector_sg.id
}
```

Create variables file: `terraform/landing-zone/variables.tf`

```hcl
# terraform/landing-zone/variables.tf

variable "aws_region" {
  description = "AWS region for the landing zone"
  type        = string
  default     = "us-east-1"
}

variable "environment" {
  description = "Environment name"
  type        = string
  default     = "production"
}

variable "project_name" {
  description = "Project name"
  type        = string
  default     = "multicloud-observability"
}
```

### Step 3.2: Deploy Landing Zone

```bash
# Initialize and deploy
cd terraform/landing-zone
terraform init
terraform plan
terraform apply -auto-approve

# Save outputs
terraform output -json > outputs.json
```

---

## 4. OpenTelemetry Collector Deployment

### Step 4.1: Create EKS Cluster for OTel Collector

Create file: `terraform/otel-cluster/main.tf`

```hcl
# terraform/otel-cluster/main.tf

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

# Import VPC data from landing zone
data "terraform_remote_state" "landing_zone" {
  backend = "local"
  config = {
    path = "../landing-zone/terraform.tfstate"
  }
}

# EKS Cluster IAM Role
resource "aws_iam_role" "eks_cluster_role" {
  name = "otel-eks-cluster-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "eks.amazonaws.com"
      }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "eks_cluster_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
  role       = aws_iam_role.eks_cluster_role.name
}

# EKS Cluster
resource "aws_eks_cluster" "otel_cluster" {
  name     = "otel-collector-cluster"
  role_arn = aws_iam_role.eks_cluster_role.arn
  version  = "1.28"

  vpc_config {
    subnet_ids              = data.terraform_remote_state.landing_zone.outputs.private_subnet_ids
    endpoint_private_access = true
    endpoint_public_access  = true
    security_group_ids      = [data.terraform_remote_state.landing_zone.outputs.otel_security_group_id]
  }

  depends_on = [
    aws_iam_role_policy_attachment.eks_cluster_policy
  ]

  tags = {
    Name = "otel-collector-cluster"
  }
}

# Node Group IAM Role
resource "aws_iam_role" "eks_node_role" {
  name = "otel-eks-node-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "ec2.amazonaws.com"
      }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "eks_worker_node_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
  role       = aws_iam_role.eks_node_role.name
}

resource "aws_iam_role_policy_attachment" "eks_cni_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
  role       = aws_iam_role.eks_node_role.name
}

resource "aws_iam_role_policy_attachment" "eks_container_registry_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
  role       = aws_iam_role.eks_node_role.name
}

# EKS Node Group
resource "aws_eks_node_group" "otel_nodes" {
  cluster_name    = aws_eks_cluster.otel_cluster.name
  node_group_name = "otel-node-group"
  node_role_arn   = aws_iam_role.eks_node_role.arn
  subnet_ids      = data.terraform_remote_state.landing_zone.outputs.private_subnet_ids

  scaling_config {
    desired_size = 3
    max_size     = 6
    min_size     = 2
  }

  instance_types = ["t3.large"]

  depends_on = [
    aws_iam_role_policy_attachment.eks_worker_node_policy,
    aws_iam_role_policy_attachment.eks_cni_policy,
    aws_iam_role_policy_attachment.eks_container_registry_policy,
  ]

  tags = {
    Name = "otel-nodes"
  }
}

# Output
output "cluster_endpoint" {
  value = aws_eks_cluster.otel_cluster.endpoint
}

output "cluster_name" {
  value = aws_eks_cluster.otel_cluster.name
}
```

Create variables: `terraform/otel-cluster/variables.tf`

```hcl
variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}
```

Deploy the cluster:

```bash
cd terraform/otel-cluster
terraform init
terraform apply -auto-approve

# Configure kubectl
aws eks update-kubeconfig --region us-east-1 --name otel-collector-cluster
```

### Step 4.2: Create OpenTelemetry Collector Configuration

Create file: `k8s/otel-collector/config.yaml`

```yaml
# k8s/otel-collector/config.yaml

apiVersion: v1
kind: ConfigMap
metadata:
  name: otel-collector-config
  namespace: observability
data:
  collector.yaml: |
    receivers:
      # OTLP Receiver for traces, metrics, and logs
      otlp:
        protocols:
          grpc:
            endpoint: 0.0.0.0:4317
          http:
            endpoint: 0.0.0.0:4318
      
      # Prometheus receiver for scraping metrics
      prometheus:
        config:
          scrape_configs:
            - job_name: 'otel-collector'
              scrape_interval: 30s
              static_configs:
                - targets: ['localhost:8888']
      
      # Kubernetes cluster receiver
      k8s_cluster:
        auth_type: serviceAccount
        node_conditions_to_report: [Ready, MemoryPressure, DiskPressure, NetworkUnavailable]
        allocatable_types_to_report: [cpu, memory, storage, ephemeral-storage]
      
      # Host metrics receiver
      hostmetrics:
        collection_interval: 30s
        scrapers:
          cpu:
          disk:
          filesystem:
          load:
          memory:
          network:
          paging:

    processors:
      # Batch processor - recommended for performance
      batch:
        timeout: 10s
        send_batch_size: 1024
        send_batch_max_size: 2048
      
      # Memory limiter to prevent OOM
      memory_limiter:
        check_interval: 1s
        limit_mib: 2000
        spike_limit_mib: 400
      
      # Resource detection processor
      resourcedetection/system:
        detectors: [env, system, docker]
        timeout: 5s
        override: false
      
      # Attributes processor for adding custom attributes
      attributes/common:
        actions:
          - key: environment
            value: production
            action: insert
          - key: platform
            value: multicloud
            action: insert
          - key: collector_version
            value: 0.90.0
            action: insert
      
      # Kubernetes attributes processor
      k8sattributes:
        auth_type: "serviceAccount"
        passthrough: false
        extract:
          metadata:
            - k8s.pod.name
            - k8s.pod.uid
            - k8s.deployment.name
            - k8s.namespace.name
            - k8s.node.name
            - k8s.pod.start_time
          labels:
            - tag_name: app.label.app
              key: app
              from: pod
            - tag_name: app.label.component
              key: component
              from: pod
        pod_association:
          - sources:
            - from: resource_attribute
              name: k8s.pod.ip
          - sources:
            - from: resource_attribute
              name: k8s.pod.uid
          - sources:
            - from: connection

    exporters:
      # New Relic exporter for metrics
      otlp/newrelic:
        endpoint: otlp.nr-data.net:4317
        headers:
          api-key: ${NEW_RELIC_LICENSE_KEY}
        tls:
          insecure: false
      
      # Logging exporter for debugging
      logging:
        loglevel: info
        sampling_initial: 5
        sampling_thereafter: 200
      
      # Prometheus exporter
      prometheus:
        endpoint: "0.0.0.0:8889"
        namespace: otelcol
        const_labels:
          env: production

    extensions:
      health_check:
        endpoint: 0.0.0.0:13133
      pprof:
        endpoint: 0.0.0.0:1777
      zpages:
        endpoint: 0.0.0.0:55679

    service:
      extensions: [health_check, pprof, zpages]
      pipelines:
        traces:
          receivers: [otlp]
          processors: [memory_limiter, resourcedetection/system, k8sattributes, attributes/common, batch]
          exporters: [otlp/newrelic, logging]
        
        metrics:
          receivers: [otlp, prometheus, k8s_cluster, hostmetrics]
          processors: [memory_limiter, resourcedetection/system, k8sattributes, attributes/common, batch]
          exporters: [otlp/newrelic, prometheus, logging]
        
        logs:
          receivers: [otlp]
          processors: [memory_limiter, resourcedetection/system, k8sattributes, attributes/common, batch]
          exporters: [otlp/newrelic, logging]
```

### Step 4.3: Deploy OpenTelemetry Collector

Create namespace and secrets:

```bash
# Create namespace
kubectl create namespace observability

# Create New Relic secret
kubectl create secret generic newrelic-secret \
  --from-literal=api-key='YOUR_NEW_RELIC_LICENSE_KEY' \
  -n observability
```

Create deployment file: `k8s/otel-collector/deployment.yaml`

```yaml
# k8s/otel-collector/deployment.yaml

apiVersion: v1
kind: ServiceAccount
metadata:
  name: otel-collector
  namespace: observability
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: otel-collector
rules:
  - apiGroups: [""]
    resources:
      - nodes
      - nodes/stats
      - nodes/proxy
      - services
      - endpoints
      - pods
      - events
      - namespaces
      - persistentvolumes
      - persistentvolumeclaims
    verbs: ["get", "list", "watch"]
  - apiGroups: ["apps"]
    resources:
      - deployments
      - daemonsets
      - replicasets
      - statefulsets
    verbs: ["get", "list", "watch"]
  - apiGroups: ["batch"]
    resources:
      - jobs
      - cronjobs
    verbs: ["get", "list", "watch"]
  - nonResourceURLs:
      - /metrics
    verbs: ["get"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: otel-collector
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: otel-collector
subjects:
  - kind: ServiceAccount
    name: otel-collector
    namespace: observability
---
apiVersion: v1
kind: Service
metadata:
  name: otel-collector
  namespace: observability
  labels:
    app: otel-collector
spec:
  type: LoadBalancer
  selector:
    app: otel-collector
  ports:
    - name: otlp-grpc
      port: 4317
      targetPort: 4317
      protocol: TCP
    - name: otlp-http
      port: 4318
      targetPort: 4318
      protocol: TCP
    - name: metrics
      port: 8888
      targetPort: 8888
      protocol: TCP
    - name: prometheus
      port: 8889
      targetPort: 8889
      protocol: TCP
    - name: health
      port: 13133
      targetPort: 13133
      protocol: TCP
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: otel-collector
  namespace: observability
  labels:
    app: otel-collector
spec:
  replicas: 3
  selector:
    matchLabels:
      app: otel-collector
  template:
    metadata:
      labels:
        app: otel-collector
    spec:
      serviceAccountName: otel-collector
      containers:
        - name: otel-collector
          image: otel/opentelemetry-collector-contrib:0.90.0
          command:
            - "/otelcol-contrib"
            - "--config=/conf/collector.yaml"
          ports:
            - containerPort: 4317
              name: otlp-grpc
            - containerPort: 4318
              name: otlp-http
            - containerPort: 8888
              name: metrics
            - containerPort: 8889
              name: prometheus
            - containerPort: 13133
              name: health
          env:
            - name: NEW_RELIC_LICENSE_KEY
              valueFrom:
                secretKeyRef:
                  name: newrelic-secret
                  key: api-key
            - name: MY_POD_IP
              valueFrom:
                fieldRef:
                  fieldPath: status.podIP
            - name: MY_NODE_NAME
              valueFrom:
                fieldRef:
                  fieldPath: spec.nodeName
          volumeMounts:
            - name: config
              mountPath: /conf
          resources:
            requests:
              memory: "512Mi"
              cpu: "500m"
            limits:
              memory: "2Gi"
              cpu: "1000m"
          livenessProbe:
            httpGet:
              path: /
              port: 13133
            initialDelaySeconds: 30
            periodSeconds: 10
          readinessProbe:
            httpGet:
              path: /
              port: 13133
            initialDelaySeconds: 10
            periodSeconds: 5
      volumes:
        - name: config
          configMap:
            name: otel-collector-config
---
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: otel-collector-hpa
  namespace: observability
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: otel-collector
  minReplicas: 3
  maxReplicas: 10
  metrics:
    - type: Resource
      resource:
        name: cpu
        target:
          type: Utilization
          averageUtilization: 70
    - type: Resource
      resource:
        name: memory
        target:
          type: Utilization
          averageUtilization: 80
```

Deploy the collector:

```bash
# Apply configuration
kubectl apply -f k8s/otel-collector/config.yaml
kubectl apply -f k8s/otel-collector/deployment.yaml

# Verify deployment
kubectl get pods -n observability
kubectl get svc -n observability

# Get LoadBalancer endpoint
export OTEL_COLLECTOR_ENDPOINT=$(kubectl get svc otel-collector -n observability -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
echo "OTel Collector Endpoint: $OTEL_COLLECTOR_ENDPOINT"
```

---

## 5. EKS Integration

### Step 5.1: Create Application EKS Cluster

Create file: `terraform/eks-app/main.tf`

```hcl
# terraform/eks-app/main.tf

provider "aws" {
  region = var.aws_region
}

module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 19.0"

  cluster_name    = "multicloud-app-eks"
  cluster_version = "1.28"

  vpc_id     = var.vpc_id
  subnet_ids = var.subnet_ids

  cluster_endpoint_public_access = true

  eks_managed_node_groups = {
    default = {
      min_size     = 2
      max_size     = 6
      desired_size = 3

      instance_types = ["t3.medium"]
      capacity_type  = "ON_DEMAND"
    }
  }

  tags = {
    Environment = "production"
    Application = "multicloud-demo"
  }
}

output "cluster_name" {
  value = module.eks.cluster_name
}

output "cluster_endpoint" {
  value = module.eks.cluster_endpoint
}
```

### Step 5.2: Deploy OTel Agent on EKS

Create file: `k8s/eks/otel-agent-daemonset.yaml`

```yaml
# k8s/eks/otel-agent-daemonset.yaml

apiVersion: v1
kind: ConfigMap
metadata:
  name: otel-agent-config
  namespace: default
data:
  config.yaml: |
    receivers:
      otlp:
        protocols:
          grpc:
            endpoint: 0.0.0.0:4317
          http:
            endpoint: 0.0.0.0:4318
      
      kubeletstats:
        collection_interval: 30s
        auth_type: "serviceAccount"
        endpoint: "https://${K8S_NODE_NAME}:10250"
        insecure_skip_verify: true
        metric_groups:
          - node
          - pod
          - container
      
      filelog:
        include: [ /var/log/pods/*/*/*.log ]
        start_at: end
        include_file_path: true
        include_file_name: false
        operators:
          - type: router
            id: get-format
            routes:
              - output: parser-docker
                expr: 'body matches "^\\{"'
              - output: parser-containerd
                expr: 'body matches "^[^ Z]+ "'
          - type: json_parser
            id: parser-docker
            output: extract_metadata_from_filepath
            timestamp:
              parse_from: attributes.time
              layout: '%Y-%m-%dT%H:%M:%S.%LZ'
          - type: regex_parser
            id: parser-containerd
            regex: '^(?P<time>[^ ^Z]+Z) (?P<stream>stdout|stderr) (?P<logtag>[^ ]*) ?(?P<log>.*)$'
            output: extract_metadata_from_filepath
            timestamp:
              parse_from: attributes.time
              layout: '%Y-%m-%dT%H:%M:%S.%LZ'
          - type: regex_parser
            id: extract_metadata_from_filepath
            regex: '^.*\/(?P<namespace>[^_]+)_(?P<pod_name>[^_]+)_(?P<uid>[a-f0-9\-]+)\/(?P<container_name>[^\._]+)\/(?P<restart_count>\d+)\.log$'
            parse_from: attributes["log.file.path"]

    processors:
      batch:
        timeout: 10s
        send_batch_size: 1024
      
      memory_limiter:
        check_interval: 1s
        limit_mib: 500
        spike_limit_mib: 100
      
      resourcedetection:
        detectors: [env, system, eks]
        timeout: 5s
      
      k8sattributes:
        auth_type: "serviceAccount"
        passthrough: false
        extract:
          metadata:
            - k8s.pod.name
            - k8s.pod.uid
            - k8s.deployment.name
            - k8s.namespace.name
            - k8s.node.name
            - k8s.pod.start_time
        pod_association:
          - sources:
            - from: resource_attribute
              name: k8s.pod.ip
          - sources:
            - from: resource_attribute
              name: k8s.pod.uid
          - sources:
            - from: connection
      
      attributes:
        actions:
          - key: cluster_name
            value: multicloud-app-eks
            action: insert
          - key: cloud_provider
            value: aws
            action: insert

    exporters:
      otlp:
        endpoint: ${OTEL_COLLECTOR_ENDPOINT}:4317
        tls:
          insecure: false
      
      logging:
        loglevel: info

    service:
      pipelines:
        traces:
          receivers: [otlp]
          processors: [memory_limiter, resourcedetection, k8sattributes, attributes, batch]
          exporters: [otlp, logging]
        
        metrics:
          receivers: [otlp, kubeletstats]
          processors: [memory_limiter, resourcedetection, k8sattributes, attributes, batch]
          exporters: [otlp, logging]
        
        logs:
          receivers: [otlp, filelog]
          processors: [memory_limiter, resourcedetection, k8sattributes, attributes, batch]
          exporters: [otlp, logging]
---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: otel-agent
  namespace: default
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: otel-agent
rules:
  - apiGroups: [""]
    resources:
      - nodes
      - nodes/stats
      - nodes/proxy
      - services
      - endpoints
      - pods
    verbs: ["get", "list", "watch"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: otel-agent
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: otel-agent
subjects:
  - kind: ServiceAccount
    name: otel-agent
    namespace: default
---
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: otel-agent
  namespace: default
  labels:
    app: otel-agent
spec:
  selector:
    matchLabels:
      app: otel-agent
  template:
    metadata:
      labels:
        app: otel-agent
    spec:
      serviceAccountName: otel-agent
      containers:
        - name: otel-agent
          image: otel/opentelemetry-collector-contrib:0.90.0
          command:
            - "/otelcol-contrib"
            - "--config=/conf/config.yaml"
          env:
            - name: K8S_NODE_NAME
              valueFrom:
                fieldRef:
                  fieldPath: spec.nodeName
            - name: K8S_POD_NAME
              valueFrom:
                fieldRef:
                  fieldPath: metadata.name
            - name: K8S_POD_NAMESPACE
              valueFrom:
                fieldRef:
                  fieldPath: metadata.namespace
            - name: K8S_POD_IP
              valueFrom:
                fieldRef:
                  fieldPath: status.podIP
            - name: OTEL_COLLECTOR_ENDPOINT
              value: "YOUR_OTEL_COLLECTOR_ENDPOINT"
          volumeMounts:
            - name: config
              mountPath: /conf
            - name: varlogpods
              mountPath: /var/log/pods
              readOnly: true
            - name: varlibdockercontainers
              mountPath: /var/lib/docker/containers
              readOnly: true
          resources:
            requests:
              memory: "256Mi"
              cpu: "200m"
            limits:
              memory: "512Mi"
              cpu: "500m"
      volumes:
        - name: config
          configMap:
            name: otel-agent-config
        - name: varlogpods
          hostPath:
            path: /var/log/pods
        - name: varlibdockercontainers
          hostPath:
            path: /var/lib/docker/containers
      tolerations:
        - effect: NoSchedule
          operator: Exists
```

Deploy the agent:

```bash
# Configure kubectl for EKS
aws eks update-kubeconfig --region us-east-1 --name multicloud-app-eks

# Replace placeholder with actual endpoint
sed -i "s/YOUR_OTEL_COLLECTOR_ENDPOINT/$OTEL_COLLECTOR_ENDPOINT/g" k8s/eks/otel-agent-daemonset.yaml

# Deploy
kubectl apply -f k8s/eks/otel-agent-daemonset.yaml

# Verify
kubectl get daemonset otel-agent
kubectl get pods -l app=otel-agent
```

### Step 5.3: Deploy Sample Application on EKS

Create file: `k8s/eks/sample-app.yaml`

```yaml
# k8s/eks/sample-app.yaml

apiVersion: apps/v1
kind: Deployment
metadata:
  name: sample-app
  namespace: default
spec:
  replicas: 3
  selector:
    matchLabels:
      app: sample-app
  template:
    metadata:
      labels:
        app: sample-app
    spec:
      containers:
        - name: app
          image: public.ecr.aws/docker/library/nginx:latest
          ports:
            - containerPort: 80
          env:
            - name: OTEL_EXPORTER_OTLP_ENDPOINT
              value: "http://localhost:4317"
            - name: OTEL_SERVICE_NAME
              value: "sample-app-eks"
            - name: OTEL_RESOURCE_ATTRIBUTES
              value: "service.name=sample-app,deployment.environment=production,cloud.provider=aws"
        - name: otel-sidecar
          image: otel/opentelemetry-collector-contrib:0.90.0
          args:
            - "--config=/conf/config.yaml"
          volumeMounts:
            - name: config
              mountPath: /conf
          env:
            - name: OTEL_COLLECTOR_ENDPOINT
              value: "${OTEL_COLLECTOR_ENDPOINT}:4317"
      volumes:
        - name: config
          configMap:
            name: otel-sidecar-config
---
apiVersion: v1
kind: Service
metadata:
  name: sample-app
  namespace: default
spec:
  type: LoadBalancer
  selector:
    app: sample-app
  ports:
    - port: 80
      targetPort: 80
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: otel-sidecar-config
  namespace: default
data:
  config.yaml: |
    receivers:
      otlp:
        protocols:
          grpc:
            endpoint: 0.0.0.0:4317
    
    processors:
      batch:
        timeout: 10s
      
      attributes:
        actions:
          - key: service.name
            value: sample-app-eks
            action: insert
    
    exporters:
      otlp:
        endpoint: ${OTEL_COLLECTOR_ENDPOINT}
        tls:
          insecure: false
    
    service:
      pipelines:
        traces:
          receivers: [otlp]
          processors: [attributes, batch]
          exporters: [otlp]
        metrics:
          receivers: [otlp]
          processors: [attributes, batch]
          exporters: [otlp]
```

---

## 6. GKE Integration

### Step 6.1: Create GKE Cluster

Create file: `terraform/gke-app/main.tf`

```hcl
# terraform/gke-app/main.tf

provider "google" {
  project = var.gcp_project_id
  region  = var.gcp_region
}

resource "google_container_cluster" "primary" {
  name     = "multicloud-app-gke"
  location = var.gcp_region

  remove_default_node_pool = true
  initial_node_count       = 1

  network    = "default"
  subnetwork = "default"

  workload_identity_config {
    workload_pool = "${var.gcp_project_id}.svc.id.goog"
  }

  addons_config {
    http_load_balancing {
      disabled = false
    }
    horizontal_pod_autoscaling {
      disabled = false
    }
  }
}

resource "google_container_node_pool" "primary_nodes" {
  name       = "primary-node-pool"
  location   = var.gcp_region
  cluster    = google_container_cluster.primary.name
  node_count = 3

  node_config {
    preemptible  = false
    machine_type = "e2-medium"

    oauth_scopes = [
      "https://www.googleapis.com/auth/cloud-platform"
    ]

    labels = {
      environment = "production"
    }

    tags = ["multicloud-gke"]
  }

  autoscaling {
    min_node_count = 2
    max_node_count = 6
  }
}

output "cluster_name" {
  value = google_container_cluster.primary.name
}

output "cluster_endpoint" {
  value = google_container_cluster.primary.endpoint
}
```

Create variables: `terraform/gke-app/variables.tf`

```hcl
variable "gcp_project_id" {
  description = "GCP Project ID"
  type        = string
}

variable "gcp_region" {
  description = "GCP region"
  type        = string
  default     = "us-central1"
}
```

Deploy:

```bash
cd terraform/gke-app
terraform init
terraform apply -auto-approve

# Configure kubectl
gcloud container clusters get-credentials multicloud-app-gke --region us-central1
```

### Step 6.2: Deploy OTel Agent on GKE

Create file: `k8s/gke/otel-agent-daemonset.yaml`

```yaml
# k8s/gke/otel-agent-daemonset.yaml

apiVersion: v1
kind: ConfigMap
metadata:
  name: otel-agent-config
  namespace: default
data:
  config.yaml: |
    receivers:
      otlp:
        protocols:
          grpc:
            endpoint: 0.0.0.0:4317
          http:
            endpoint: 0.0.0.0:4318
      
      kubeletstats:
        collection_interval: 30s
        auth_type: "serviceAccount"
        endpoint: "https://${K8S_NODE_NAME}:10250"
        insecure_skip_verify: true
        metric_groups:
          - node
          - pod
          - container
      
      filelog:
        include: [ /var/log/pods/*/*/*.log ]
        start_at: end
        include_file_path: true
        operators:
          - type: router
            id: get-format
            routes:
              - output: parser-containerd
                expr: 'body matches "^[^ Z]+ "'
          - type: regex_parser
            id: parser-containerd
            regex: '^(?P<time>[^ ^Z]+Z) (?P<stream>stdout|stderr) (?P<logtag>[^ ]*) ?(?P<log>.*)$'
            output: extract_metadata_from_filepath
            timestamp:
              parse_from: attributes.time
              layout: '%Y-%m-%dT%H:%M:%S.%LZ'
          - type: regex_parser
            id: extract_metadata_from_filepath
            regex: '^.*\/(?P<namespace>[^_]+)_(?P<pod_name>[^_]+)_(?P<uid>[a-f0-9\-]+)\/(?P<container_name>[^\._]+)\/(?P<restart_count>\d+)\.log$'
            parse_from: attributes["log.file.path"]

    processors:
      batch:
        timeout: 10s
      
      memory_limiter:
        check_interval: 1s
        limit_mib: 500
      
      resourcedetection:
        detectors: [env, system, gcp]
        timeout: 5s
      
      k8sattributes:
        auth_type: "serviceAccount"
        passthrough: false
        extract:
          metadata:
            - k8s.pod.name
            - k8s.pod.uid
            - k8s.deployment.name
            - k8s.namespace.name
            - k8s.node.name
        pod_association:
          - sources:
            - from: resource_attribute
              name: k8s.pod.ip
      
      attributes:
        actions:
          - key: cluster_name
            value: multicloud-app-gke
            action: insert
          - key: cloud_provider
            value: gcp
            action: insert

    exporters:
      otlp:
        endpoint: ${OTEL_COLLECTOR_ENDPOINT}:4317
        tls:
          insecure: false
      
      logging:
        loglevel: info

    service:
      pipelines:
        traces:
          receivers: [otlp]
          processors: [memory_limiter, resourcedetection, k8sattributes, attributes, batch]
          exporters: [otlp, logging]
        
        metrics:
          receivers: [otlp, kubeletstats]
          processors: [memory_limiter, resourcedetection, k8sattributes, attributes, batch]
          exporters: [otlp, logging]
        
        logs:
          receivers: [otlp, filelog]
          processors: [memory_limiter, resourcedetection, k8sattributes, attributes, batch]
          exporters: [otlp, logging]
---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: otel-agent
  namespace: default
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: otel-agent
rules:
  - apiGroups: [""]
    resources:
      - nodes
      - nodes/stats
      - nodes/proxy
      - services
      - endpoints
      - pods
    verbs: ["get", "list", "watch"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: otel-agent
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: otel-agent
subjects:
  - kind: ServiceAccount
    name: otel-agent
    namespace: default
---
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: otel-agent
  namespace: default
  labels:
    app: otel-agent
spec:
  selector:
    matchLabels:
      app: otel-agent
  template:
    metadata:
      labels:
        app: otel-agent
    spec:
      serviceAccountName: otel-agent
      containers:
        - name: otel-agent
          image: otel/opentelemetry-collector-contrib:0.90.0
          command:
            - "/otelcol-contrib"
            - "--config=/conf/config.yaml"
          env:
            - name: K8S_NODE_NAME
              valueFrom:
                fieldRef:
                  fieldPath: spec.nodeName
            - name: OTEL_COLLECTOR_ENDPOINT
              value: "YOUR_OTEL_COLLECTOR_ENDPOINT"
          volumeMounts:
            - name: config
              mountPath: /conf
            - name: varlogpods
              mountPath: /var/log/pods
              readOnly: true
          resources:
            requests:
              memory: "256Mi"
              cpu: "200m"
            limits:
              memory: "512Mi"
              cpu: "500m"
      volumes:
        - name: config
          configMap:
            name: otel-agent-config
        - name: varlogpods
          hostPath:
            path: /var/log/pods
      tolerations:
        - effect: NoSchedule
          operator: Exists
```

Deploy:

```bash
# Replace endpoint
sed -i "s/YOUR_OTEL_COLLECTOR_ENDPOINT/$OTEL_COLLECTOR_ENDPOINT/g" k8s/gke/otel-agent-daemonset.yaml

# Deploy
kubectl apply -f k8s/gke/otel-agent-daemonset.yaml

# Verify
kubectl get daemonset otel-agent
```

---

## 7. AKS Integration

### Step 7.1: Create AKS Cluster

Create file: `terraform/aks-app/main.tf`

```hcl
# terraform/aks-app/main.tf

provider "azurerm" {
  features {}
}

resource "azurerm_resource_group" "rg" {
  name     = "multicloud-app-rg"
  location = var.azure_location
}

resource "azurerm_kubernetes_cluster" "aks" {
  name                = "multicloud-app-aks"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  dns_prefix          = "multicloud-aks"

  default_node_pool {
    name       = "default"
    node_count = 3
    vm_size    = "Standard_D2_v2"
    
    enable_auto_scaling = true
    min_count          = 2
    max_count          = 6
  }

  identity {
    type = "SystemAssigned"
  }

  network_profile {
    network_plugin    = "azure"
    load_balancer_sku = "standard"
  }

  tags = {
    Environment = "production"
  }
}

output "cluster_name" {
  value = azurerm_kubernetes_cluster.aks.name
}

output "kube_config" {
  value     = azurerm_kubernetes_cluster.aks.kube_config_raw
  sensitive = true
}
```

Variables: `terraform/aks-app/variables.tf`

```hcl
variable "azure_location" {
  description = "Azure location"
  type        = string
  default     = "East US"
}
```

Deploy:

```bash
cd terraform/aks-app
terraform init
terraform apply -auto-approve

# Configure kubectl
az aks get-credentials --resource-group multicloud-app-rg --name multicloud-app-aks
```

### Step 7.2: Deploy OTel Agent on AKS

Create file: `k8s/aks/otel-agent-daemonset.yaml`

```yaml
# k8s/aks/otel-agent-daemonset.yaml

apiVersion: v1
kind: ConfigMap
metadata:
  name: otel-agent-config
  namespace: default
data:
  config.yaml: |
    receivers:
      otlp:
        protocols:
          grpc:
            endpoint: 0.0.0.0:4317
          http:
            endpoint: 0.0.0.0:4318
      
      kubeletstats:
        collection_interval: 30s
        auth_type: "serviceAccount"
        endpoint: "https://${K8S_NODE_NAME}:10250"
        insecure_skip_verify: true
        metric_groups:
          - node
          - pod
          - container
      
      filelog:
        include: [ /var/log/containers/*.log ]
        start_at: end
        include_file_path: true

    processors:
      batch:
        timeout: 10s
      
      memory_limiter:
        check_interval: 1s
        limit_mib: 500
      
      resourcedetection:
        detectors: [env, system, azure]
        timeout: 5s
      
      k8sattributes:
        auth_type: "serviceAccount"
        passthrough: false
        extract:
          metadata:
            - k8s.pod.name
            - k8s.pod.uid
            - k8s.deployment.name
            - k8s.namespace.name
            - k8s.node.name
      
      attributes:
        actions:
          - key: cluster_name
            value: multicloud-app-aks
            action: insert
          - key: cloud_provider
            value: azure
            action: insert

    exporters:
      otlp:
        endpoint: ${OTEL_COLLECTOR_ENDPOINT}:4317
        tls:
          insecure: false
      
      logging:
        loglevel: info

    service:
      pipelines:
        traces:
          receivers: [otlp]
          processors: [memory_limiter, resourcedetection, k8sattributes, attributes, batch]
          exporters: [otlp, logging]
        
        metrics:
          receivers: [otlp, kubeletstats]
          processors: [memory_limiter, resourcedetection, k8sattributes, attributes, batch]
          exporters: [otlp, logging]
        
        logs:
          receivers: [otlp, filelog]
          processors: [memory_limiter, resourcedetection, k8sattributes, attributes, batch]
          exporters: [otlp, logging]
---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: otel-agent
  namespace: default
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: otel-agent
rules:
  - apiGroups: [""]
    resources:
      - nodes
      - nodes/stats
      - pods
      - services
      - endpoints
    verbs: ["get", "list", "watch"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: otel-agent
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: otel-agent
subjects:
  - kind: ServiceAccount
    name: otel-agent
    namespace: default
---
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: otel-agent
  namespace: default
  labels:
    app: otel-agent
spec:
  selector:
    matchLabels:
      app: otel-agent
  template:
    metadata:
      labels:
        app: otel-agent
    spec:
      serviceAccountName: otel-agent
      containers:
        - name: otel-agent
          image: otel/opentelemetry-collector-contrib:0.90.0
          command:
            - "/otelcol-contrib"
            - "--config=/conf/config.yaml"
          env:
            - name: K8S_NODE_NAME
              valueFrom:
                fieldRef:
                  fieldPath: spec.nodeName
            - name: OTEL_COLLECTOR_ENDPOINT
              value: "YOUR_OTEL_COLLECTOR_ENDPOINT"
          volumeMounts:
            - name: config
              mountPath: /conf
            - name: varlogcontainers
              mountPath: /var/log/containers
              readOnly: true
          resources:
            requests:
              memory: "256Mi"
              cpu: "200m"
            limits:
              memory: "512Mi"
              cpu: "500m"
      volumes:
        - name: config
          configMap:
            name: otel-agent-config
        - name: varlogcontainers
          hostPath:
            path: /var/log/containers
      tolerations:
        - effect: NoSchedule
          operator: Exists
```

Deploy:

```bash
# Replace endpoint
sed -i "s/YOUR_OTEL_COLLECTOR_ENDPOINT/$OTEL_COLLECTOR_ENDPOINT/g" k8s/aks/otel-agent-daemonset.yaml

# Deploy
kubectl apply -f k8s/aks/otel-agent-daemonset.yaml

# Verify
kubectl get daemonset otel-agent
```

---

## 8. New Relic Configuration

### Step 8.1: Setup New Relic Account

1. **Sign up for New Relic**: Visit https://newrelic.com/signup
2. **Get License Key**:
   - Navigate to Account Settings → API Keys
   - Copy your License Key

### Step 8.2: Create Custom Dashboards

Create file: `newrelic/dashboards/multicloud-overview.json`

```json
{
  "name": "Multi-Cloud Observability Overview",
  "description": "Overview dashboard for EKS, GKE, and AKS clusters",
  "permissions": "PUBLIC_READ_WRITE",
  "pages": [
    {
      "name": "Cluster Health",
      "description": "Overall cluster health metrics",
      "widgets": [
        {
          "title": "CPU Usage by Cluster",
          "layout": {
            "column": 1,
            "row": 1,
            "width": 4,
            "height": 3
          },
          "visualization": {
            "id": "viz.line"
          },
          "rawConfiguration": {
            "nrqlQueries": [
              {
                "accountId": YOUR_ACCOUNT_ID,
                "query": "SELECT average(k8s.node.cpu.utilization) FROM Metric WHERE cluster_name IN ('multicloud-app-eks', 'multicloud-app-gke', 'multicloud-app-aks') FACET cluster_name TIMESERIES"
              }
            ]
          }
        },
        {
          "title": "Memory Usage by Cluster",
          "layout": {
            "column": 5,
            "row": 1,
            "width": 4,
            "height": 3
          },
          "visualization": {
            "id": "viz.line"
          },
          "rawConfiguration": {
            "nrqlQueries": [
              {
                "accountId": YOUR_ACCOUNT_ID,
                "query": "SELECT average(k8s.node.memory.utilization) FROM Metric WHERE cluster_name IN ('multicloud-app-eks', 'multicloud-app-gke', 'multicloud-app-aks') FACET cluster_name TIMESERIES"
              }
            ]
          }
        },
        {
          "title": "Pod Count by Cluster",
          "layout": {
            "column": 9,
            "row": 1,
            "width": 4,
            "height": 3
          },
          "visualization": {
            "id": "viz.billboard"
          },
          "rawConfiguration": {
            "nrqlQueries": [
              {
                "accountId": YOUR_ACCOUNT_ID,
                "query": "SELECT uniqueCount(k8s.pod.name) FROM Metric WHERE cluster_name IN ('multicloud-app-eks', 'multicloud-app-gke', 'multicloud-app-aks') FACET cluster_name"
              }
            ]
          }
        },
        {
          "title": "Request Latency by Cloud Provider",
          "layout": {
            "column": 1,
            "row": 4,
            "width": 6,
            "height": 3
          },
          "visualization": {
            "id": "viz.line"
          },
          "rawConfiguration": {
            "nrqlQueries": [
              {
                "accountId": YOUR_ACCOUNT_ID,
                "query": "SELECT percentile(duration, 50, 95, 99) FROM Span WHERE cloud_provider IN ('aws', 'gcp', 'azure') FACET cloud_provider TIMESERIES"
              }
            ]
          }
        },
        {
          "title": "Error Rate by Cluster",
          "layout": {
            "column": 7,
            "row": 4,
            "width": 6,
            "height": 3
          },
          "visualization": {
            "id": "viz.line"
          },
          "rawConfiguration": {
            "nrqlQueries": [
              {
                "accountId": YOUR_ACCOUNT_ID,
                "query": "SELECT percentage(count(*), WHERE error IS true) FROM Span FACET cluster_name TIMESERIES"
              }
            ]
          }
        },
        {
          "title": "Top Services by Request Count",
          "layout": {
            "column": 1,
            "row": 7,
            "width": 4,
            "height": 3
          },
          "visualization": {
            "id": "viz.bar"
          },
          "rawConfiguration": {
            "nrqlQueries": [
              {
                "accountId": YOUR_ACCOUNT_ID,
                "query": "SELECT count(*) FROM Span FACET service.name LIMIT 10"
              }
            ]
          }
        },
        {
          "title": "Network Traffic by Cluster",
          "layout": {
            "column": 5,
            "row": 7,
            "width": 4,
            "height": 3
          },
          "visualization": {
            "id": "viz.area"
          },
          "rawConfiguration": {
            "nrqlQueries": [
              {
                "accountId": YOUR_ACCOUNT_ID,
                "query": "SELECT sum(k8s.pod.network.io) FROM Metric FACET cluster_name TIMESERIES"
              }
            ]
          }
        },
        {
          "title": "Log Volume by Severity",
          "layout": {
            "column": 9,
            "row": 7,
            "width": 4,
            "height": 3
          },
          "visualization": {
            "id": "viz.pie"
          },
          "rawConfiguration": {
            "nrqlQueries": [
              {
                "accountId": YOUR_ACCOUNT_ID,
                "query": "SELECT count(*) FROM Log FACET severity"
              }
            ]
          }
        }
      ]
    },
    {
      "name": "Service Performance",
      "description": "Service-level performance metrics",
      "widgets": [
        {
          "title": "Service Map",
          "layout": {
            "column": 1,
            "row": 1,
            "width": 12,
            "height": 4
          },
          "visualization": {
            "id": "viz.service-map"
          },
          "rawConfiguration": {
            "nrqlQueries": [
              {
                "accountId": YOUR_ACCOUNT_ID,
                "query": "FROM Span SELECT count(*)"
              }
            ]
          }
        },
        {
          "title": "Throughput by Service",
          "layout": {
            "column": 1,
            "row": 5,
            "width": 6,
            "height": 3
          },
          "visualization": {
            "id": "viz.line"
          },
          "rawConfiguration": {
            "nrqlQueries": [
              {
                "accountId": YOUR_ACCOUNT_ID,
                "query": "SELECT rate(count(*), 1 minute) FROM Span FACET service.name TIMESERIES"
              }
            ]
          }
        },
        {
          "title": "Response Time Distribution",
          "layout": {
            "column": 7,
            "row": 5,
            "width": 6,
            "height": 3
          },
          "visualization": {
            "id": "viz.histogram"
          },
          "rawConfiguration": {
            "nrqlQueries": [
              {
                "accountId": YOUR_ACCOUNT_ID,
                "query": "SELECT histogram(duration, 20, 10) FROM Span"
              }
            ]
          }
        }
      ]
    },
    {
      "name": "Infrastructure",
      "description": "Infrastructure-level metrics",
      "widgets": [
        {
          "title": "Node CPU Usage",
          "layout": {
            "column": 1,
            "row": 1,
            "width": 6,
            "height": 3
          },
          "visualization": {
            "id": "viz.heatmap"
          },
          "rawConfiguration": {
            "nrqlQueries": [
              {
                "accountId": YOUR_ACCOUNT_ID,
                "query": "SELECT average(k8s.node.cpu.utilization) FROM Metric FACET k8s.node.name, cluster_name"
              }
            ]
          }
        },
        {
          "title": "Node Memory Usage",
          "layout": {
            "column": 7,
            "row": 1,
            "width": 6,
            "height": 3
          },
          "visualization": {
            "id": "viz.heatmap"
          },
          "rawConfiguration": {
            "nrqlQueries": [
              {
                "accountId": YOUR_ACCOUNT_ID,
                "query": "SELECT average(k8s.node.memory.utilization) FROM Metric FACET k8s.node.name, cluster_name"
              }
            ]
          }
        },
        {
          "title": "Disk Usage by Cluster",
          "layout": {
            "column": 1,
            "row": 4,
            "width": 6,
            "height": 3
          },
          "visualization": {
            "id": "viz.area"
          },
          "rawConfiguration": {
            "nrqlQueries": [
              {
                "accountId": YOUR_ACCOUNT_ID,
                "query": "SELECT average(k8s.node.filesystem.usage) FROM Metric FACET cluster_name TIMESERIES"
              }
            ]
          }
        },
        {
          "title": "Pod Restarts",
          "layout": {
            "column": 7,
            "row": 4,
            "width": 6,
            "height": 3
          },
          "visualization": {
            "id": "viz.table"
          },
          "rawConfiguration": {
            "nrqlQueries": [
              {
                "accountId": YOUR_ACCOUNT_ID,
                "query": "SELECT latest(k8s.pod.restartCount) FROM Metric FACET k8s.pod.name, k8s.namespace.name, cluster_name WHERE k8s.pod.restartCount > 0"
              }
            ]
          }
        }
      ]
    }
  ]
}
```

### Step 8.3: Create Alerts

Create file: `newrelic/alerts/alert-policies.json`

```json
{
  "policies": [
    {
      "name": "Multi-Cloud Critical Alerts",
      "incident_preference": "PER_CONDITION",
      "conditions": [
        {
          "type": "NRQL",
          "name": "High CPU Usage",
          "enabled": true,
          "nrql": {
            "query": "SELECT average(k8s.node.cpu.utilization) FROM Metric FACET cluster_name"
          },
          "signal": {
            "aggregation_window": 60,
            "evaluation_offset": 3
          },
          "terms": [
            {
              "threshold": 85,
              "threshold_duration": 300,
              "threshold_occurrences": "ALL",
              "operator": "ABOVE",
              "priority": "CRITICAL"
            },
            {
              "threshold": 75,
              "threshold_duration": 300,
              "threshold_occurrences": "ALL",
              "operator": "ABOVE",
              "priority": "WARNING"
            }
          ],
          "violation_time_limit_seconds": 86400
        },
        {
          "type": "NRQL",
          "name": "High Memory Usage",
          "enabled": true,
          "nrql": {
            "query": "SELECT average(k8s.node.memory.utilization) FROM Metric FACET cluster_name"
          },
          "signal": {
            "aggregation_window": 60,
            "evaluation_offset": 3
          },
          "terms": [
            {
              "threshold": 90,
              "threshold_duration": 300,
              "threshold_occurrences": "ALL",
              "operator": "ABOVE",
              "priority": "CRITICAL"
            },
            {
              "threshold": 80,
              "threshold_duration": 300,
              "threshold_occurrences": "ALL",
              "operator": "ABOVE",
              "priority": "WARNING"
            }
          ]
        },
        {
          "type": "NRQL",
          "name": "High Error Rate",
          "enabled": true,
          "nrql": {
            "query": "SELECT percentage(count(*), WHERE error IS true) FROM Span FACET service.name"
          },
          "signal": {
            "aggregation_window": 60,
            "evaluation_offset": 3
          },
          "terms": [
            {
              "threshold": 5,
              "threshold_duration": 300,
              "threshold_occurrences": "ALL",
              "operator": "ABOVE",
              "priority": "CRITICAL"
            }
          ]
        },
        {
          "type": "NRQL",
          "name": "Slow Response Time",
          "enabled": true,
          "nrql": {
            "query": "SELECT percentile(duration, 95) FROM Span FACET service.name"
          },
          "signal": {
            "aggregation_window": 60,
            "evaluation_offset": 3
          },
          "terms": [
            {
              "threshold": 2000,
              "threshold_duration": 300,
              "threshold_occurrences": "ALL",
              "operator": "ABOVE",
              "priority": "WARNING"
            }
          ]
        },
        {
          "type": "NRQL",
          "name": "Pod Restart Rate",
          "enabled": true,
          "nrql": {
            "query": "SELECT rate(sum(k8s.pod.restartCount), 1 minute) FROM Metric FACET k8s.pod.name"
          },
          "signal": {
            "aggregation_window": 60,
            "evaluation_offset": 3
          },
          "terms": [
            {
              "threshold": 3,
              "threshold_duration": 600,
              "threshold_occurrences": "ALL",
              "operator": "ABOVE",
              "priority": "WARNING"
            }
          ]
        }
      ]
    }
  ]
}
```

### Step 8.4: Setup Alert Notification Channels

Create Python script: `scripts/setup-newrelic-alerts.py`

```python
#!/usr/bin/env python3
# scripts/setup-newrelic-alerts.py

import requests
import json
import os

NEW_RELIC_API_KEY = os.environ.get('NEW_RELIC_API_KEY')
NEW_RELIC_ACCOUNT_ID = os.environ.get('NEW_RELIC_ACCOUNT_ID')

def create_notification_channel(channel_config):
    """Create a notification channel in New Relic"""
    url = f'https://api.newrelic.com/v2/alerts_channels.json'
    
    headers = {
        'Api-Key': NEW_RELIC_API_KEY,
        'Content-Type': 'application/json'
    }
    
    response = requests.post(url, headers=headers, json=channel_config)
    
    if response.status_code == 201:
        print(f"Created notification channel: {channel_config['channel']['name']}")
        return response.json()
    else:
        print(f"Failed to create channel: {response.status_code} - {response.text}")
        return None

def create_alert_policy(policy_config):
    """Create an alert policy in New Relic"""
    url = f'https://api.newrelic.com/v2/alerts_policies.json'
    
    headers = {
        'Api-Key': NEW_RELIC_API_KEY,
        'Content-Type': 'application/json'
    }
    
    response = requests.post(url, headers=headers, json={'policy': policy_config})
    
    if response.status_code == 201:
        print(f"Created alert policy: {policy_config['name']}")
        return response.json()
    else:
        print(f"Failed to create policy: {response.status_code} - {response.text}")
        return None

def create_nrql_condition(policy_id, condition_config):
    """Create a NRQL alert condition"""
    url = f'https://api.newrelic.com/v2/alerts_nrql_conditions/policies/{policy_id}.json'
    
    headers = {
        'Api-Key': NEW_RELIC_API_KEY,
        'Content-Type': 'application/json'
    }
    
    response = requests.post(url, headers=headers, json={'nrql_condition': condition_config})
    
    if response.status_code == 201:
        print(f"Created NRQL condition: {condition_config['name']}")
        return response.json()
    else:
        print(f"Failed to create condition: {response.status_code} - {response.text}")
        return None

def main():
    # Example: Create Slack notification channel
    slack_channel = {
        'channel': {
            'name': 'Multi-Cloud Alerts - Slack',
            'type': 'slack',
            'configuration': {
                'url': 'https://hooks.slack.com/services/YOUR/SLACK/WEBHOOK',
                'channel': '#observability-alerts'
            }
        }
    }
    
    # Example: Create email notification channel
    email_channel = {
        'channel': {
            'name': 'Multi-Cloud Alerts - Email',
            'type': 'email',
            'configuration': {
                'recipients': 'ops-team@example.com',
                'include_json_attachment': 'true'
            }
        }
    }
    
    # Create channels
    slack_result = create_notification_channel(slack_channel)
    email_result = create_notification_channel(email_channel)
    
    # Create alert policy
    policy = {
        'name': 'Multi-Cloud Critical Alerts',
        'incident_preference': 'PER_CONDITION'
    }
    
    policy_result = create_alert_policy(policy)
    
    if policy_result:
        policy_id = policy_result['policy']['id']
        
        # Create NRQL conditions
        conditions = [
            {
                'name': 'High CPU Usage',
                'enabled': True,
                'terms': [{
                    'duration': '5',
                    'operator': 'above',
                    'priority': 'critical',
                    'threshold': '85',
                    'time_function': 'all'
                }],
                'type': 'static',
                'nrql': {
                    'query': f"SELECT average(k8s.node.cpu.utilization) FROM Metric WHERE accountId = '{NEW_RELIC_ACCOUNT_ID}' FACET cluster_name",
                    'since_value': '3'
                },
                'value_function': 'single_value'
            },
            {
                'name': 'High Memory Usage',
                'enabled': True,
                'terms': [{
                    'duration': '5',
                    'operator': 'above',
                    'priority': 'critical',
                    'threshold': '90',
                    'time_function': 'all'
                }],
                'type': 'static',
                'nrql': {
                    'query': f"SELECT average(k8s.node.memory.utilization) FROM Metric WHERE accountId = '{NEW_RELIC_ACCOUNT_ID}' FACET cluster_name",
                    'since_value': '3'
                },
                'value_function': 'single_value'
            }
        ]
        
        for condition in conditions:
            create_nrql_condition(policy_id, condition)

if __name__ == '__main__':
    main()
```

Make it executable and run:

```bash
chmod +x scripts/setup-newrelic-alerts.py

# Set environment variables
export NEW_RELIC_API_KEY="your-api-key"
export NEW_RELIC_ACCOUNT_ID="your-account-id"

# Run script
python3 scripts/setup-newrelic-alerts.py
```

---

## 9. Monitoring & Alerting

### Step 9.1: Create Unified Monitoring Script

Create file: `scripts/monitor-multicloud.sh`

```bash
#!/bin/bash
# scripts/monitor-multicloud.sh

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo "=================================="
echo "Multi-Cloud Observability Monitor"
echo "=================================="
echo ""

# Function to check cluster health
check_cluster_health() {
    local cluster_name=$1
    local context=$2
    
    echo -e "${YELLOW}Checking ${cluster_name}...${NC}"
    
    kubectl config use-context $context > /dev/null 2>&1
    
    # Check nodes
    echo "  Nodes:"
    kubectl get nodes --no-headers 2>/dev/null | while read line; do
        node_name=$(echo $line | awk '{print $1}')
        node_status=$(echo $line | awk '{print $2}')
        
        if [ "$node_status" == "Ready" ]; then
            echo -e "    ${GREEN}✓${NC} $node_name: $node_status"
        else
            echo -e "    ${RED}✗${NC} $node_name: $node_status"
        fi
    done
    
    # Check OTel agent
    echo "  OTel Agent:"
    otel_ready=$(kubectl get daemonset otel-agent -o jsonpath='{.status.numberReady}' 2>/dev/null || echo "0")
    otel_desired=$(kubectl get daemonset otel-agent -o jsonpath='{.status.desiredNumberScheduled}' 2>/dev/null || echo "0")
    
    if [ "$otel_ready" == "$otel_desired" ] && [ "$otel_ready" != "0" ]; then
        echo -e "    ${GREEN}✓${NC} $otel_ready/$otel_desired pods ready"
    else
        echo -e "    ${RED}✗${NC} $otel_ready/$otel_desired pods ready"
    fi
    
    # Check resource usage
    echo "  Resource Usage:"
    kubectl top nodes 2>/dev/null | tail -n +2 | while read line; do
        node_name=$(echo $line | awk '{print $1}')
        cpu=$(echo $line | awk '{print $2}')
        memory=$(echo $line | awk '{print $4}')
        echo "    - $node_name: CPU=$cpu, Memory=$memory"
    done
    
    echo ""
}

# Check EKS
echo "=== Amazon EKS ==="
aws eks update-kubeconfig --region us-east-1 --name multicloud-app-eks > /dev/null 2>&1
check_cluster_health "EKS" "$(kubectl config current-context)"

# Check GKE
echo "=== Google GKE ==="
gcloud container clusters get-credentials multicloud-app-gke --region us-central1 > /dev/null 2>&1
check_cluster_health "GKE" "$(kubectl config current-context)"

# Check AKS
echo "=== Azure AKS ==="
az aks get-credentials --resource-group multicloud-app-rg --name multicloud-app-aks --overwrite-existing > /dev/null 2>&1
check_cluster_health "AKS" "$(kubectl config current-context)"

# Check Central OTel Collector
echo "=== Central OTel Collector ==="
aws eks update-kubeconfig --region us-east-1 --name otel-collector-cluster > /dev/null 2>&1
kubectl config set-context --current --namespace=observability > /dev/null 2>&1

echo "  Collector Status:"
otel_ready=$(kubectl get deployment otel-collector -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0")
otel_desired=$(kubectl get deployment otel-collector -o jsonpath='{.spec.replicas}' 2>/dev/null || echo "0")

if [ "$otel_ready" == "$otel_desired" ] && [ "$otel_ready" != "0" ]; then
    echo -e "    ${GREEN}✓${NC} $otel_ready/$otel_desired pods ready"
else
    echo -e "    ${RED}✗${NC} $otel_ready/$otel_desired pods ready"
fi

# Get collector endpoint
echo "  Collector Endpoint:"
collector_lb=$(kubectl get svc otel-collector -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || echo "N/A")
echo "    $collector_lb"

echo ""
echo "=== Summary ==="
echo "All clusters checked. Review output above for any issues."
echo "Dashboard: https://one.newrelic.com/"
```

Make executable:

```bash
chmod +x scripts/monitor-multicloud.sh
./scripts/monitor-multicloud.sh
```

### Step 9.2: Create Load Testing Script

Create file: `scripts/load-test.sh`

```bash
#!/bin/bash
# scripts/load-test.sh

# Generate load across all clusters
echo "Starting load test across all clusters..."

# Function to generate traffic
generate_traffic() {
    local cluster=$1
    local endpoint=$2
    
    echo "Generating traffic for $cluster..."
    
    for i in {1..1000}; do
        curl -s -o /dev/null -w "%{http_code}" http://$endpoint/ &
        sleep 0.1
    done
    
    wait
    echo "$cluster load test complete"
}

# Get service endpoints
EKS_ENDPOINT=$(kubectl --context eks-context get svc sample-app -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
GKE_ENDPOINT=$(kubectl --context gke-context get svc sample-app -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
AKS_ENDPOINT=$(kubectl --context aks-context get svc sample-app -o jsonpath='{.status.loadBalancer.ingress[0].ip}')

# Run load tests in parallel
generate_traffic "EKS" $EKS_ENDPOINT &
generate_traffic "GKE" $GKE_ENDPOINT &
generate_traffic "AKS" $AKS_ENDPOINT &

wait

echo "Load test complete. Check New Relic dashboard for results."
```

---

## 10. Best Practices

### 10.1: Security Best Practices

```bash
# Rotate secrets regularly
kubectl create secret generic newrelic-secret \
  --from-literal=api-key='NEW_KEY' \
  --dry-run=client -o yaml | kubectl apply -f -

# Use RBAC properly
# Ensure service accounts have minimal permissions

# Enable audit logging
# AWS EKS
aws eks update-cluster-config \
  --name multicloud-app-eks \
  --logging '{"clusterLogging":[{"types":["api","audit","authenticator"],"enabled":true}]}'

# Enable encryption at rest
# Ensure all clusters have encryption enabled for secrets
```

### 10.2: Cost Optimization

```yaml
# Set resource requests and limits
resources:
  requests:
    memory: "256Mi"
    cpu: "250m"
  limits:
    memory: "512Mi"
    cpu: "500m"

# Use HPA for auto-scaling
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: otel-agent-hpa
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: DaemonSet
    name: otel-agent
  minReplicas: 1
  maxReplicas: 3
  metrics:
  - type: Resource
    resource:
      name: cpu
      target:
        type: Utilization
        averageUtilization: 70
```

### 10.3: Data Retention Policies

```yaml
# Configure data retention in OTel Collector
processors:
  batch:
    timeout: 10s
    send_batch_size: 1024
    send_batch_max_size: 2048
  
  # Drop old data
  filter/dropold:
    traces:
      span:
        - 'attributes["time"] < now() - duration("24h")'
```

### 10.4: Backup and Disaster Recovery

```bash
#!/bin/bash
# scripts/backup-configs.sh

# Backup all Kubernetes configurations
mkdir -p backups/$(date +%Y%m%d)

# Backup EKS configs
kubectl --context eks-context get all --all-namespaces -o yaml > backups/$(date +%Y%m%d)/eks-backup.yaml

# Backup GKE configs
kubectl --context gke-context get all --all-namespaces -o yaml > backups/$(date +%Y%m%d)/gke-backup.yaml

# Backup AKS configs
kubectl --context aks-context get all --all-namespaces -o yaml > backups/$(date +%Y%m%d)/aks-backup.yaml

# Backup Terraform state
cp terraform/**/terraform.tfstate backups/$(date +%Y%m%d)/

echo "Backup complete: backups/$(date +%Y%m%d)/"
```

---

## Appendix A: Troubleshooting

### Common Issues

**Issue 1: OTel Agent not sending data**

```bash
# Check agent logs
kubectl logs -l app=otel-agent --tail=50

# Verify collector endpoint
kubectl exec -it <otel-agent-pod> -- curl -v http://$OTEL_COLLECTOR_ENDPOINT:4317

# Check network policies
kubectl get networkpolicies
```

**Issue 2: High memory usage**

```bash
# Increase memory limits
kubectl set resources daemonset/otel-agent --limits=memory=1Gi

# Adjust batch processor
# Edit configmap to reduce batch size
```

**Issue 3: Missing metrics in New Relic**

```bash
# Verify API key
kubectl get secret newrelic-secret -o jsonpath='{.data.api-key}' | base64 -d

# Check exporter configuration
kubectl describe configmap otel-collector-config

# Test connection
kubectl exec -it <collector-pod> -- curl -v https://otlp.nr-data.net:4317
```

---

## Appendix B: Useful Commands

```bash
# Switch between clusters
kubectl config use-context <context-name>
kubectl config get-contexts

# View logs across all pods
kubectl logs -l app=otel-agent --all-containers=true --tail=100

# Port forward to collector
kubectl port-forward svc/otel-collector 4317:4317 -n observability

# Debug pod networking
kubectl run -it --rm debug --image=nicolaka/netshoot --restart=Never -- /bin/bash

# Export metrics
kubectl port-forward svc/otel-collector 8889:8889 -n observability
curl http://localhost:8889/metrics

# Check resource usage
kubectl top nodes
kubectl top pods --all-namespaces
```

---

## Appendix C: Architecture Diagrams

```
┌─────────────────────────────────────────────────────────────────┐
│                      Data Flow Architecture                      │
└─────────────────────────────────────────────────────────────────┘

Application Pods                  OTel Agent (DaemonSet)
    │                                     │
    │ OTLP (gRPC/HTTP)                   │
    └────────────────────────────────────┤
                                          │
                                          │ Process & Enrich
                                          │ - Add cluster metadata
                                          │ - Add cloud provider tags
                                          │ - Batch data
                                          │
                                          ▼
                            Central OTel Collector (AWS)
                                          │
                                          │ Aggregate & Route
                                          │ - Memory limiting
                                          │ - Resource detection
                                          │ - Additional processing
                                          │
                                          ▼
                                    New Relic OTLP
                                          │
                                          ▼
                            ┌─────────────────────────┐
                            │   New Relic Platform    │
                            │  - Metrics              │
                            │  - Traces               │
                            │  - Logs                 │
                            │  - Dashboards           │
                            │  - Alerts               │
                            └─────────────────────────┘
```

---

## Conclusion

This comprehensive guide provides a production-ready multi-cloud observability platform using OpenTelemetry and New Relic. The architecture supports:

✅ **Scalability**: Auto-scaling across all components  
✅ **Reliability**: High availability with multiple replicas  
✅ **Security**: RBAC, secrets management, and encrypted communication  
✅ **Cost Optimization**: Efficient resource usage and data batching  
✅ **Monitoring**: Comprehensive dashboards and alerting  
✅ **Multi-Cloud**: Unified view across AWS, GCP, and Azure  

### Next Steps

1. **Customize dashboards** for your specific use cases
2. **Tune alert thresholds** based on your SLOs
3. **Implement SLIs/SLOs** for critical services
4. **Add custom instrumentation** to applications
5. **Set up log correlation** for better troubleshooting
6. **Implement cost tracking** for observability infrastructure

---
