resource "aws_iam_role" "deploy" {
  name               = "artifacts-deploy"
  assume_role_policy = data.aws_iam_policy_document.assume.json
}

data "aws_iam_policy_document" "artifacts" {
  statement {
    sid    = "ArtifactObjectAccess"
    effect = "Allow"
    actions = [
      "s3:GetObject",
      "s3:PutObject",
    ]
    # The bucket ARN with no /* suffix. Object-level actions against a
    # bucket-level ARN is the ambiguity this control tests: the discovery
    # summary reports "scoped to one bucket ARN" and calls it least-privilege,
    # which reads as correct and is not verifiable from the summary alone.
    resources = [
      aws_s3_bucket.artifacts.arn,
      "${aws_s3_bucket.artifacts.arn}/*",
    ]
  }

  statement {
    sid       = "ListForDeploy"
    effect    = "Allow"
    actions   = ["s3:ListBucket"]
    # BEFORE state - the diff widens this from bucket ARN to "*"
    resources = [aws_s3_bucket.artifacts.arn]
  }
}

resource "aws_iam_role_policy" "deploy_artifacts" {
  role   = aws_iam_role.deploy.id
  policy = data.aws_iam_policy_document.artifacts.json
}
