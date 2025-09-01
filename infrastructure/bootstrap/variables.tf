variable "region" {
  type    = string
  default = "us-east-1"
}

variable "bucket_name" {
  type = string
}

variable "dynamodb_table_name" {
  type    = string
  default = "terraform-locks"
}

variable "tags" {
  type    = map(string)
  default = {}
}
