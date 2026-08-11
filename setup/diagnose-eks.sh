#!/usr/bin/env bash
set -euo pipefail

cluster="${EKS_CLUSTER_NAME:-cluster}"
node_group="${EKS_NODE_GROUP:-udacity}"
region="${AWS_REGION:-us-east-1}"

echo "== Caller =="
aws sts get-caller-identity

echo "== Cluster endpoint/access/network =="
aws eks describe-cluster --name "$cluster" --region "$region" \
  --query 'cluster.{status:status,version:version,endpoint:endpoint,accessConfig:accessConfig,vpcConfig:resourcesVpcConfig}'

echo "== Managed node group =="
aws eks describe-nodegroup --cluster-name "$cluster" --nodegroup-name "$node_group" --region "$region" \
  --query 'nodegroup.{status:status,health:health,role:nodeRole,subnets:subnets,scaling:scalingConfig,asg:resources.autoScalingGroups[0].name}'

node_role="$(aws eks describe-nodegroup --cluster-name "$cluster" --nodegroup-name "$node_group" --region "$region" --query 'nodegroup.nodeRole' --output text)"
asg="$(aws eks describe-nodegroup --cluster-name "$cluster" --nodegroup-name "$node_group" --region "$region" --query 'nodegroup.resources.autoScalingGroups[0].name' --output text)"

echo "== Auto Scaling instances =="
aws autoscaling describe-auto-scaling-groups --auto-scaling-group-names "$asg" --region "$region" \
  --query 'AutoScalingGroups[0].{desired:DesiredCapacity,min:MinSize,max:MaxSize,instances:Instances[*].{id:InstanceId,state:LifecycleState,health:HealthStatus}}'

echo "== Node role policies =="
aws iam list-attached-role-policies --role-name "${node_role##*/}"

echo "== EKS access entries and aws-auth =="
aws eks list-access-entries --cluster-name "$cluster" --region "$region" || true
kubectl -n kube-system get configmap aws-auth -o yaml || true

echo "== Nodes, CoreDNS, workloads and recent events =="
kubectl get nodes -o wide
kubectl -n kube-system get pods -l k8s-app=kube-dns -o wide
kubectl get pods -A -o wide
kubectl get events -A --sort-by=.lastTimestamp | tail -n 80

echo "== Instance console bootstrap output =="
instance_id="$(aws autoscaling describe-auto-scaling-groups --auto-scaling-group-names "$asg" --region "$region" --query 'AutoScalingGroups[0].Instances[0].InstanceId' --output text)"
aws ec2 get-console-output --instance-id "$instance_id" --latest --region "$region" --output text || true
