# modules/resilience/variables.tf

variable "stage" {
  description = "Deployment stage."
  type        = string
}

variable "stop_condition_alarm_arn" {
  description = "ARN of the CloudWatch alarm used as a stop condition for FIS experiments."
  type        = string
}

variable "tags" {
  description = "Tags to apply to all resources."
  type        = map(string)
  default     = {}
}
