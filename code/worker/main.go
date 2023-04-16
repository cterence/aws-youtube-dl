package main

import (
	"bytes"
	"context"
	"fmt"
	"io/ioutil"
	"net/url"
	"os"

	"github.com/aws/aws-lambda-go/events"
	"github.com/aws/aws-lambda-go/lambda"

	"github.com/aws/aws-sdk-go-v2/aws"
	"github.com/aws/aws-sdk-go-v2/config"
	"github.com/aws/aws-sdk-go-v2/feature/s3/manager"
	"github.com/aws/aws-sdk-go-v2/service/s3"
	"github.com/aws/aws-sdk-go-v2/service/sns"
	"github.com/aws/aws-sdk-go-v2/service/sqs"
	"github.com/kkdai/youtube/v2"
)

func HandleRequest(ctx context.Context, event events.SQSEvent) error {
	for _, message := range event.Records {
		// Get the video ID from the SQS message body
		videoID := message.Body

		// Download the video from YouTube and upload it to S3
		// ...

		//
		client := youtube.Client{}

		video, err := client.GetVideo(videoID)
		if err != nil {
			panic(err)
		}

		formats := video.Formats.WithAudioChannels() // only get videos with audio
		stream, _, err := client.GetStream(video, &formats[0])
		if err != nil {
			panic(err)
		}

		cfg, err := config.LoadDefaultConfig(context.Background())
		if err != nil {
			panic(err)
		}

		svc := s3.NewFromConfig(cfg)

		data, err := ioutil.ReadAll(stream)
		if err != nil {
			panic(err)
		}

		bucket := aws.String(os.Getenv("BUCKET_NAME"))
		key := aws.String(fmt.Sprintf("%s.mp4", video.Title))

		_, err = svc.PutObject(context.TODO(), &s3.PutObjectInput{
			Bucket: bucket,
			Key:    key,
			Body:   manager.ReadSeekCloser(bytes.NewReader(data)),
		})

		if err != nil {
			panic(err)
		}

		// Delete the SQS message to remove it from the queue
		sqsClient := sqs.NewFromConfig(cfg)
		_, err = sqsClient.DeleteMessage(ctx, &sqs.DeleteMessageInput{
			QueueUrl:      aws.String(os.Getenv("QUEUE_URL")),
			ReceiptHandle: aws.String(message.ReceiptHandle),
		})

		if err != nil {
			return err
		}

		snsClient := sns.NewFromConfig(cfg)
		_, err = snsClient.Publish(ctx, &sns.PublishInput{
			Message:  aws.String(fmt.Sprintf("Video https://%s.s3.eu-west-3.amazonaws.com/%s is uploaded to S3", *bucket, url.QueryEscape(*key))),
			TopicArn: aws.String(os.Getenv("TOPIC_ARN")),
		})

		if err != nil {
			return err
		}
	}

	return nil
}

func main() {
	lambda.Start(HandleRequest)
}
