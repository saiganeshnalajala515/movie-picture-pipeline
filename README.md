# Movie Picture CI/CD Pipeline

This project contains a React frontend and a Flask backend for a simple movie catalog. I set up the infrastructure and delivery process so both applications can be tested, containerized, pushed to Amazon ECR, and deployed to Amazon EKS through GitHub Actions.

## Project overview

The application has two services:

- **Frontend:** React application served on port `3000`
- **Backend:** Flask API served on port `5000`

The frontend calls the backend `/movies` endpoint and displays the movie list. Both applications run as Kubernetes deployments and are exposed through AWS LoadBalancer services.

## Repository structure

```text
.
|-- .github/workflows/
|   |-- frontend-ci.yaml
|   |-- frontend-cd.yaml
|   |-- backend-ci.yaml
|   `-- backend-cd.yaml
|-- setup/
|   |-- terraform/
|   |-- diagnose-eks.sh
|   `-- init.sh
|-- starter/
|   |-- frontend/
|   |   |-- Dockerfile
|   |   |-- k8s/
|   |   `-- src/
|   `-- backend/
|       |-- Dockerfile
|       |-- k8s/
|       `-- movies/
`-- OPERATIONS.md
```

## What I implemented

- Separate CI workflows for the frontend and backend
- Separate CD workflows for the frontend and backend
- Pull-request and path-based CI triggers
- Main-branch and path-based deployment triggers
- Manual execution with `workflow_dispatch`
- Parallel lint and test jobs
- Docker builds that run only after lint and tests pass
- ECR images tagged with the Git commit SHA
- Kubernetes deployment with rollout verification
- Encrypted GitHub Actions Secrets for AWS authentication
- Terraform for the VPC, ECR, EKS, IAM, node group, and GitHub deployment role
- Failure summaries in GitHub Actions

## CI/CD workflow

### Continuous integration

The CI workflows run for pull requests against `main` when files for the relevant application change.

```text
Lint ----\
          > Docker build
Test ----/
```

Lint and tests run in parallel. The Docker build starts only when both jobs pass.

### Continuous deployment

The CD workflows run after relevant changes are pushed to `main` or when started manually.

```text
Lint ----\
          > Build image > Push to ECR > Deploy to EKS > Verify rollout
Test ----/
```

Each image is tagged with `${{ github.sha }}`. The deployment job updates the Kubernetes manifest with that exact image, applies the Kustomize configuration, and waits for the deployment rollout.

## GitHub repository configuration

The Udacity lab does not allow creation of a GitHub OIDC provider, so the deployment workflows use a dedicated least-privilege IAM user. Its credentials are stored only in GitHub's encrypted Actions Secrets and are never committed to the repository.

Create two GitHub Actions secrets and one repository variable:

| Setting | Type | Purpose |
|---|---|---|
| `AWS_ACCESS_KEY_ID` | Secret | Access key for the dedicated deployment user |
| `AWS_SECRET_ACCESS_KEY` | Secret | Secret key for the dedicated deployment user |
| `BACKEND_API_URL` | Variable | Public backend LoadBalancer URL used during the frontend build |

For the existing Udacity cluster, the repository settings can be configured with:

```powershell
& ".\setup\configure-github.ps1"
```

This script creates or updates the dedicated deployment user, stores a new key pair directly in GitHub Actions Secrets, configures Kubernetes access, and sets the backend URL. It does not print or commit credential values.

## Infrastructure setup

The Terraform configuration creates:

- VPC, public subnet, optional private subnet, route tables, and internet access
- ECR repositories for the frontend and backend
- EKS cluster and managed node group
- IAM roles and policies for EKS workers
- Dedicated IAM deployment user and EKS access entry
- EKS access entries for worker and deployment roles

Apply the infrastructure:

```bash
cd setup/terraform
terraform init
terraform plan
terraform apply
```

The default AWS region is `us-east-1` and the EKS cluster name is `cluster`.

## EKS node registration issue

During deployment, the managed node group showed `ACTIVE`, but Kubernetes reported zero nodes. CoreDNS and both application pods remained Pending.

I checked the node group, EC2 instance, subnet routes, security groups, instance profile, IAM policies, cluster endpoint configuration, and EC2 console output. The console output showed that AL2023 `nodeadm` could not call `ec2:DescribeInstances` because the Udacity organization applied an explicit Service Control Policy deny.

The worker role already had the required IAM policies, so adding another IAM allow policy would not solve the problem. I fixed the bootstrap path by:

1. Enabling `API_AND_CONFIG_MAP` authentication on the EKS cluster.
2. Creating a separate worker role and EKS node access entry.
3. Enabling the AL2023 `InstanceIdNodeName` feature in a launch template.
4. Creating the replacement node group `udacity-fixed`.
5. Waiting for the replacement node and CoreDNS to become healthy.
6. Removing the original broken node group after verification.

The Terraform configuration in this repository includes the same fix so the infrastructure can be recreated consistently.

## Local frontend commands

```bash
cd starter/frontend
nvm use
npm ci
npm run lint
CI=true npm test
```

Build and run the frontend container:

```bash
docker build \
  --build-arg REACT_APP_MOVIE_API_URL=http://localhost:5000 \
  --tag mp-frontend:latest .

docker run --name mp-frontend -p 3000:3000 -d mp-frontend:latest
```

## Local backend commands

```bash
cd starter/backend
pipenv sync --dev
pipenv run lint
pipenv run test
```

Build and run the backend container:

```bash
docker build --tag mp-backend:latest .
docker run --name mp-backend -p 5000:5000 -d mp-backend:latest
curl http://localhost:5000/movies
```

## Kubernetes deployment

Configure access to the cluster:

```bash
aws eks update-kubeconfig --name cluster --region us-east-1
```

Deploy the backend:

```bash
cd starter/backend/k8s
kustomize edit set image backend=ECR_BACKEND_URL:IMAGE_TAG
kustomize build | kubectl apply -f -
```

Deploy the frontend:

```bash
cd starter/frontend/k8s
kustomize edit set image frontend=ECR_FRONTEND_URL:IMAGE_TAG
kustomize build | kubectl apply -f -
```

## Verification

```bash
kubectl get nodes -o wide
kubectl -n kube-system get pods -l k8s-app=kube-dns -o wide
kubectl get deployments,pods,services -o wide
kubectl rollout status deployment/backend --timeout=5m
kubectl rollout status deployment/frontend --timeout=5m
```

Final deployment result:

- Replacement node group `udacity-fixed` is active
- One Kubernetes node is Ready
- Both CoreDNS pods are Running
- Backend deployment is `1/1`
- Frontend deployment is `1/1`
- Backend `/movies` returns HTTP `200` with movie data
- Frontend returns HTTP `200`

More troubleshooting and recovery commands are documented in [OPERATIONS.md](OPERATIONS.md).

## Cleanup

AWS resources should be destroyed when the project is no longer being tested to avoid unnecessary charges:

```bash
cd setup/terraform
terraform destroy
```

## License

See [LICENSE.md](LICENSE.md).
