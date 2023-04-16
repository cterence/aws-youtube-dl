data "aws_iam_policy_document" "worker_assume_role" {
  statement {
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }

    actions = ["sts:AssumeRole"]
  }
}

data "aws_iam_policy_document" "worker_lambda" {
  statement {
    effect = "Allow"
    resources = [
      aws_s3_bucket.this.arn,
      "${aws_s3_bucket.this.arn}/*",
    ]
    actions = [
      "s3:PutObject*",
      "s3:GetObject",
      "s3:ListBucket",
    ]
  }

  statement {
    effect    = "Allow"
    resources = [aws_sqs_queue.video_download_queue.arn]
    actions = [
      "sqs:ReceiveMessage",
      "sqs:DeleteMessage",
      "sqs:GetQueueAttributes",
    ]
  }

  statement {
    effect    = "Allow"
    resources = [aws_sns_topic.upload_notification.arn]
    actions   = ["sns:Publish"]
  }

  statement {
    effect    = "Allow"
    resources = ["arn:aws:logs:${local.region}:${local.account_id}:*"]
    actions   = ["logs:CreateLogGroup"]
  }

  statement {
    effect    = "Allow"
    resources = ["arn:aws:logs:${local.region}:${local.account_id}:log-group:/aws/lambda/*"]
    actions = [
      "logs:CreateLogStream",
      "logs:PutLogEvents"
    ]
  }
}

resource "aws_iam_role" "worker_lambda" {
  name = "worker_lambda"
  inline_policy {
    name   = "policy"
    policy = data.aws_iam_policy_document.worker_lambda.json
  }
  assume_role_policy = data.aws_iam_policy_document.worker_assume_role.json
}

resource "null_resource" "worker_build" {
  provisioner "local-exec" {
    working_dir = "./code/worker"
    command     = "GOOS=linux GOARCH=amd64 CGO_ENABLED=0 go build -o main main.go"
  }

  triggers = {
    "recompile" = filebase64sha256("./code/worker/main.go")
  }
}

data "archive_file" "worker_lambda" {
  type        = "zip"
  source_file = "./code/worker/main"
  output_path = "./code/worker/main.zip"

  depends_on = [
    null_resource.worker_build
  ]
}

resource "aws_lambda_function" "worker_lambda" {
  filename         = "./code/worker/main.zip"
  function_name    = "worker"
  role             = aws_iam_role.worker_lambda.arn
  handler          = "main"
  timeout          = 600
  runtime          = "go1.x"
  source_code_hash = data.archive_file.worker_lambda.output_base64sha256

  tracing_config {
    mode = "Active"
  }

  environment {
    variables = {
      BUCKET_NAME = aws_s3_bucket.this.bucket
      QUEUE_URL   = aws_sqs_queue.video_download_queue.url
      TOPIC_ARN   = aws_sns_topic.upload_notification.arn
    }
  }
}

resource "aws_lambda_event_source_mapping" "video_download_worker" {
  event_source_arn = aws_sqs_queue.video_download_queue.arn
  function_name    = aws_lambda_function.worker_lambda.arn
  batch_size       = 1
}

resource "aws_sns_topic" "upload_notification" {
  name = "upload_notification"
}

resource "aws_sns_topic_subscription" "user_updates_sqs_target" {
  topic_arn = aws_sns_topic.upload_notification.arn
  protocol  = "email"
  endpoint  = var.subscribing_email
}
