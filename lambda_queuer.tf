data "aws_iam_policy_document" "queuer_assume_role" {
  statement {
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }

    actions = ["sts:AssumeRole"]
  }
}

data "aws_iam_policy_document" "queuer_lambda" {
  statement {
    effect = "Allow"

    resources = ["*"]

    actions = ["sqs:*"]
  }
}

resource "aws_iam_role" "queuer_lambda" {
  name = "queuer_lambda"
  inline_policy {
    name   = "policy"
    policy = data.aws_iam_policy_document.queuer_lambda.json
  }
  assume_role_policy = data.aws_iam_policy_document.queuer_assume_role.json
}

resource "null_resource" "queuer_build" {
  provisioner "local-exec" {
    working_dir = "./code/queuer"
    command     = "GOOS=linux GOARCH=amd64 CGO_ENABLED=0 go build -o main main.go"
  }

  triggers = {
    "recompile" = filebase64sha256("./code/queuer/main.go")
  }
}

data "archive_file" "queuer_lambda" {
  type        = "zip"
  source_file = "./code/queuer/main"
  output_path = "./code/queuer/main.zip"

  depends_on = [
    null_resource.queuer_build
  ]
}

resource "aws_lambda_function" "queuer_lambda" {
  # If the file is not in the current working directory you will need to include a
  # path.module in the filename.
  filename      = "./code/queuer/main.zip"
  function_name = "queuer"
  role          = aws_iam_role.queuer_lambda.arn
  handler       = "main"
  timeout       = 600

  source_code_hash = data.archive_file.queuer_lambda.output_base64sha256

  runtime = "go1.x"

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

resource "aws_lambda_permission" "apigateway_invoke_queuer_lambda" {
  statement_id  = "AllowExecutionFromAPIGateway"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.queuer_lambda.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.test_api.execution_arn}/*/*"
}

resource "aws_api_gateway_integration" "test_integration" {
  rest_api_id             = aws_api_gateway_rest_api.test_api.id
  resource_id             = aws_api_gateway_resource.test_resource.id
  http_method             = aws_api_gateway_method.test_method.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.queuer_lambda.invoke_arn
}
