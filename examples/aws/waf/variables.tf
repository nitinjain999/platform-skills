variable "name" {
  type        = string
  description = "Name prefix applied to all WAF resources."

  validation {
    condition     = can(regex("^[a-zA-Z0-9-_]+$", var.name)) && length(var.name) <= 32
    error_message = "Name must be alphanumeric, hyphens, or underscores, max 32 chars."
  }
}

variable "default_tags" {
  type        = map(string)
  description = "Tags applied to all resources via provider default_tags."
  default     = {}
}

variable "default_action" {
  type        = string
  description = "Default WebACL action when no rule matches. 'allow' for public sites, 'block' for internal APIs."
  default     = "allow"

  validation {
    condition     = contains(["allow", "block"], var.default_action)
    error_message = "Must be 'allow' or 'block'."
  }
}

variable "trusted_cidrs" {
  type        = list(string)
  description = "CIDR blocks that bypass all WAF rules (priority 0 allow rule). Use for known-safe internal IPs."
  default     = []
}

variable "rate_limit" {
  type        = number
  description = "Maximum requests per IP per 5-minute window before blocking. Set 0 to disable rate limiting."
  default     = 2000

  validation {
    condition     = var.rate_limit == 0 || (var.rate_limit >= 100 && var.rate_limit <= 2000000000)
    error_message = "Rate limit must be 0 (disabled) or between 100 and 2,000,000,000."
  }
}

variable "rate_limit_scope_path" {
  type        = string
  description = "URI path prefix to scope the rate limit to (e.g. '/api/'). Empty string applies to all paths."
  default     = ""
}

variable "blocked_country_codes" {
  type        = list(string)
  description = "ISO 3166-1 alpha-2 country codes to block (e.g. ['RU', 'KP']). Empty list disables geo blocking."
  default     = []
}

variable "enable_bot_control" {
  type        = bool
  description = "Enable AWS Managed Bot Control rule group (paid — charged per request inspected)."
  default     = false
}

variable "enable_atp" {
  type        = bool
  description = "Enable Account Takeover Prevention rule group (paid). Requires login_path to be set."
  default     = false
}

variable "login_path" {
  type        = string
  description = "Login endpoint URI for ATP rule group (e.g. '/login'). Required when enable_atp = true."
  default     = null
}

variable "cloudwatch_log_retention_days" {
  type        = number
  description = "CloudWatch log group retention in days for WAF logs."
  default     = 30

  validation {
    condition     = contains([1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1827, 3653], var.cloudwatch_log_retention_days)
    error_message = "Must be a valid CloudWatch retention value."
  }
}
