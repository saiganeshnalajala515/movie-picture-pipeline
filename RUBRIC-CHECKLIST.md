# Rubric Checklist

## Frontend CI

- [x] File is `.github/workflows/frontend-ci.yaml`
- [x] Workflow name is `Frontend Continuous Integration`
- [x] Runs on pull requests against `main`
- [x] Runs only for frontend/workflow changes
- [x] Supports manual execution
- [x] Lint and test jobs run independently in parallel
- [x] Lint job checks out code, sets up NodeJS, restores cache, installs dependencies, and runs `npm run lint`
- [x] Test job checks out code, sets up NodeJS, restores cache, installs dependencies, and runs `npm test`
- [x] Build uses `needs: [lint, test]`
- [x] Build repeats NodeJS setup, cache, dependency installation, and tests before Docker build

## Backend CI

- [x] File is `.github/workflows/backend-ci.yaml`
- [x] Workflow name is `Backend Continuous Integration`
- [x] Runs on pull requests against `main`
- [x] Supports manual execution
- [x] Lint and test jobs run in parallel
- [x] Dependencies are cached and installed with Pipenv
- [x] Build uses `needs: [lint, test]`
- [x] Backend Docker image is built only after lint and tests pass

## Frontend CD

- [x] File is `.github/workflows/frontend-cd.yaml`
- [x] Workflow name is `Frontend Continuous Deployment`
- [x] Runs on pushes/merges to `main`
- [x] Supports manual execution
- [x] Lint and test jobs run before build
- [x] Build uses `REACT_APP_MOVIE_API_URL`
- [x] Uses `aws-actions/amazon-ecr-login`
- [x] Reads AWS credentials from encrypted GitHub Secrets without embedding key values
- [x] Pushes a commit-SHA-tagged image to ECR
- [x] Deploys with `kubectl` and verifies rollout

## Backend CD

- [x] File is `.github/workflows/backend-cd.yaml`
- [x] Workflow name is `Backend Continuous Deployment`
- [x] Runs on pushes/merges to `main`
- [x] Supports manual execution
- [x] Lint and test jobs run before build
- [x] Uses `aws-actions/amazon-ecr-login`
- [x] Reads AWS credentials from encrypted GitHub Secrets without embedding key values
- [x] Pushes a commit-SHA-tagged image to ECR
- [x] Deploys with `kubectl` and verifies rollout

## Submission evidence

- [x] EKS node is Ready
- [x] CoreDNS is Running
- [x] Frontend and backend pods are Running
- [x] Frontend URL returns HTTP 200
- [x] Backend `/movies` returns HTTP 200 with movie data
- [ ] Run all four workflows in GitHub and capture successful run screenshots after pushing the project
