# EKS Operations Notes

## Issue observed

The EKS cluster and managed node group were both ACTIVE, and the Auto Scaling group had one running EC2 instance. Kubernetes still reported zero nodes, so CoreDNS and the application pods could not be scheduled.

## Checks performed

I checked the following areas before changing the infrastructure:

- Managed node-group health and desired capacity
- EC2 instance and system status
- Worker instance profile and IAM role trust policy
- Required worker IAM policies
- Public subnet address assignment and default route
- EKS cluster endpoint access
- Cluster security group rules
- EKS authentication mode
- EC2 instance console and `nodeadm` output

The instance console showed an explicit organization-level deny for `ec2:DescribeInstances`. This caused `nodeadm-config.service` to fail before kubelet could register the node.

## Fix applied

- Changed EKS authentication to `API_AND_CONFIG_MAP`
- Created a new worker IAM role
- Added an EKS node access entry
- Enabled `InstanceIdNodeName` in AL2023 node configuration
- Created replacement node group `udacity-fixed`
- Verified the replacement node and CoreDNS
- Deleted the broken node group after successful verification

## Diagnostic commands

```bash
aws eks describe-cluster --name cluster --region us-east-1
aws eks describe-nodegroup \
  --cluster-name cluster \
  --nodegroup-name udacity-fixed \
  --region us-east-1

kubectl get nodes -o wide
kubectl get pods -A -o wide
kubectl get events -A --sort-by=.lastTimestamp
```

The helper script collects the same information:

```bash
cd setup
./diagnose-eks.sh
```

## Expected healthy state

```text
Node:                 Ready
CoreDNS:              2/2 Running
Backend deployment:   1/1 Available
Frontend deployment:  1/1 Available
Backend HTTP check:   200
Frontend HTTP check:  200
```

## GitHub Actions access

GitHub Actions uses a dedicated IAM deployment user because the Udacity lab blocks creation of OIDC providers. The repository needs these settings:

- GitHub Actions secret: `AWS_ACCESS_KEY_ID`
- GitHub Actions secret: `AWS_SECRET_ACCESS_KEY`
- Repository variable: `BACKEND_API_URL`

Credential values are stored only as encrypted GitHub Secrets and are not committed to the repository.
