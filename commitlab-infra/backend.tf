terraform {
  backend "s3" {
    # These values must be replaced with your specific S3 bucket and DynamoDB table.
    # They should match the values you export as environment variables in the Quick Start guide.
    # Example from _Requirements/other_data.txt:
    # bucket         = "dima-test-tfstate-bucket"
    # dynamodb_table = "dima-test-tf-lock-table"
    bucket         = "dima-test-tfstate-bucket"
    dynamodb_table = "dima-test-tf-lock-table"
    key            = "commitlab/terraform.tfstate"
    region         = "eu-north-1"
  }
}