package main

import (
	"context"
	"os"

	"github.com/aws/aws-lambda-go/events"
	"github.com/aws/aws-lambda-go/lambda"

	"github.com/aws/aws-sdk-go-v2/aws"
	"github.com/aws/aws-sdk-go-v2/config"
	"github.com/aws/aws-sdk-go-v2/service/sqs"
	"github.com/aws/aws-xray-sdk-go/instrumentation/awsv2"
)

func HandleRequest(ctx context.Context, event events.APIGatewayProxyRequest) (events.APIGatewayProxyResponse, error) {
	// Parse the video ID from the query string parameters
	videoID, ok := event.QueryStringParameters["id"]
	if !ok {
		return events.APIGatewayProxyResponse{Body: "missing id parameter", StatusCode: 400}, nil
	}

	// Create an SQS client
	cfg, _ := config.LoadDefaultConfig(ctx)

	awsv2.AWSV2Instrumentor(&cfg.APIOptions)

	sqsClient := sqs.NewFromConfig(cfg)

	// Send the video ID to the SQS queue
	_, err := sqsClient.SendMessage(ctx, &sqs.SendMessageInput{
		QueueUrl:    aws.String(os.Getenv("QUEUE_URL")),
		MessageBody: aws.String(videoID),
	})

	if err != nil {
		return events.APIGatewayProxyResponse{Body: "error sending message to queue", StatusCode: 500}, err
	}

	// Return a success response to the client
	return events.APIGatewayProxyResponse{Body: "video download job queued", StatusCode: 202}, nil
}

func main() {
	lambda.Start(HandleRequest)
}
