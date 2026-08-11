param(
    [string]$Repository = "saiganeshnalajala515/movie-picture-pipeline",
    [string]$AwsProfile = "default",
    [string]$Region = "us-east-1",
    [string]$ClusterName = "cluster",
    [string]$BackendApiUrl = "http://ad6736b2e7dbb4a5fa356e294b7f3270-1661092213.us-east-1.elb.amazonaws.com"
)

$ErrorActionPreference = "Stop"
$userName = "github-action-user"

function Invoke-AwsJson {
    param([Parameter(Mandatory)][string[]]$Arguments)
    $result = & aws @Arguments --profile $AwsProfile --region $Region --output json
    if ($LASTEXITCODE -ne 0) { throw "AWS command failed: aws $($Arguments -join ' ')" }
    if ([string]::IsNullOrWhiteSpace($result)) { return $null }
    return ($result | ConvertFrom-Json)
}

function Test-AwsCommand {
    param([Parameter(Mandatory)][string[]]$Arguments)
    $previousPreference = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    try {
        & aws @Arguments --profile $AwsProfile --region $Region --output json 2>&1 | Out-Null
        return ($LASTEXITCODE -eq 0)
    } finally {
        $ErrorActionPreference = $previousPreference
    }
}

try {
    gh auth status | Out-Host
    if ($LASTEXITCODE -ne 0) { throw "GitHub CLI is not authenticated" }

    $identity = Invoke-AwsJson -Arguments @("sts", "get-caller-identity")
    $accountId = $identity.Account
    $userArn = "arn:aws:iam::${accountId}:user/$userName"

    Write-Host "Configuring GitHub Actions access for $Repository..."

    if (-not (Test-AwsCommand -Arguments @("iam", "get-user", "--user-name", $userName))) {
        throw "The Terraform-managed IAM user github-action-user was not found."
    }

    $entries = @((Invoke-AwsJson -Arguments @("eks", "list-access-entries", "--cluster-name", $ClusterName)).accessEntries)
    if ($entries -notcontains $userArn) {
        Invoke-AwsJson -Arguments @(
            "eks", "create-access-entry",
            "--cluster-name", $ClusterName,
            "--principal-arn", $userArn,
            "--type", "STANDARD"
        ) | Out-Null
    }

    Invoke-AwsJson -Arguments @(
        "eks", "associate-access-policy",
        "--cluster-name", $ClusterName,
        "--principal-arn", $userArn,
        "--policy-arn", "arn:aws:eks::aws:cluster-access-policy/AmazonEKSAdminPolicy",
        "--access-scope", "type=namespace,namespaces=default"
    ) | Out-Null

    $existingKeys = @((Invoke-AwsJson -Arguments @("iam", "list-access-keys", "--user-name", $userName)).AccessKeyMetadata)
    if ($existingKeys.Count -ge 2) {
        throw "The dedicated IAM user already has two access keys. Delete an unused key before rerunning."
    }

    $newKey = (Invoke-AwsJson -Arguments @("iam", "create-access-key", "--user-name", $userName)).AccessKey
    $newKey.AccessKeyId | gh secret set AWS_ACCESS_KEY_ID --repo $Repository
    if ($LASTEXITCODE -ne 0) { throw "Failed to set AWS_ACCESS_KEY_ID" }
    $newKey.SecretAccessKey | gh secret set AWS_SECRET_ACCESS_KEY --repo $Repository
    if ($LASTEXITCODE -ne 0) { throw "Failed to set AWS_SECRET_ACCESS_KEY" }
    gh variable set BACKEND_API_URL --body $BackendApiUrl --repo $Repository
    if ($LASTEXITCODE -ne 0) { throw "Failed to set BACKEND_API_URL" }

    foreach ($oldKey in $existingKeys) {
        Invoke-AwsJson -Arguments @(
            "iam", "delete-access-key",
            "--user-name", $userName,
            "--access-key-id", $oldKey.AccessKeyId
        ) | Out-Null
    }

    Clear-Variable newKey
    Write-Host "GitHub Actions configuration completed."
    Write-Host "Configured encrypted secrets: AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY"
    Write-Host "Configured variable: BACKEND_API_URL"
    Write-Host "No credential values were written to the repository."
} finally {
    Clear-Variable newKey -ErrorAction SilentlyContinue
}
