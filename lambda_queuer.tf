data "aws_iam_policy_document" "queueing_assume_role" {
  statement {
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }

    actions = ["sts:AssumeRole"]
  }
}

data "aws_iam_policy_document" "queueing_lambda" {
  statement {
    effect    = "Allow"
    resources = [aws_sqs_queue.video_download_queue.arn]
    actions   = ["sqs:SendMessage"]
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

resource "aws_iam_role" "queueing_lambda" {
  name = "queueing_lambda"
  inline_policy {
    name   = "policy"
    policy = data.aws_iam_policy_document.queueing_lambda.json
  }
  assume_role_policy = data.aws_iam_policy_document.queueing_assume_role.json
}

resource "null_resource" "queueing_build" {
  provisioner "local-exec" {
    working_dir = "./code/queueing"
    command     = "GOOS=linux GOARCH=amd64 CGO_ENABLED=0 go build -o main main.go"
  }

  triggers = {
    "recompile" = filebase64sha256("./code/queueing/main.go")
  }
}

data "archive_file" "queueing_lambda" {
  type        = "zip"
  source_file = "./code/queueing/main"
  output_path = "./code/queueing/main.zip"

  depends_on = [
    null_resource.queueing_build
  ]
}

resource "aws_lambda_function" "queueing_lambda" {
  # If the file is not in the current working directory you will need to include a
  # path.module in the filename.
  filename         = "./code/queueing/main.zip"
  function_name    = "queueing"
  role             = aws_iam_role.queueing_lambda.arn
  handler          = "main"
  timeout          = 600
  runtime          = "go1.x"
  source_code_hash = data.archive_file.queueing_lambda.output_base64sha256


  tracing_config {
    mode = "PassThrough"
  }

  environment {
    variables = {
      QUEUE_URL = aws_sqs_queue.video_download_queue.url
    }
  }
}

resource "aws_sqs_queue" "video_download_queue" {
  name                       = "video-download-queue"
  visibility_timeout_seconds = 3000
}

resource "aws_lambda_permission" "apigateway_invoke_queueing_lambda" {
  statement_id  = "AllowExecutionFromAPIGateway"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.queueing_lambda.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.this.execution_arn}/*/*"
}

resource "aws_api_gateway_integration" "this" {
  rest_api_id             = aws_api_gateway_rest_api.this.id
  resource_id             = aws_api_gateway_resource.this.id
  http_method             = aws_api_gateway_method.this.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.queueing_lambda.invoke_arn
}
