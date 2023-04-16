resource "aws_s3_bucket" "this" {
  bucket = "downloaded-youtube-videos"
}

data "aws_iam_policy_document" "s3_bucket_policy" {
  version = "2012-10-17"

  statement {
    effect = "Allow"

    principals {
      type        = "AWS"
      identifiers = ["*"]
    }

    actions = [
      "s3:GetObject",
    ]

    resources = [
      "arn:aws:s3:::downloaded-youtube-videos/*",
    ]
  }
}

resource "aws_s3_bucket_policy" "this" {
  bucket = aws_s3_bucket.this.id
  policy = data.aws_iam_policy_document.s3_bucket_policy.json
}

resource "aws_s3_bucket_lifecycle_configuration" "this" {
  bucket = aws_s3_bucket.this.id

  rule {
    id     = "delete-all"
    status = "Enabled"

    expiration {
      days = 1
    }
  }
}
