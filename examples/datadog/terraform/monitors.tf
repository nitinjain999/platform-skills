terraform {
  required_providers {
    datadog = {
      source  = "DataDog/datadog"
      version = "~> 3.0"
    }
  }
}

provider "datadog" {
  api_url = "https://api.datadoghq.eu/"   # EU site — change for US
  # api_key and app_key read from DD_API_KEY and DD_APP_KEY env vars
}

# ---------------------------------------------------------------------------
# Error Rate Monitor
# ---------------------------------------------------------------------------
resource "datadog_monitor" "orders_error_rate" {
  name    = "orders-service high error rate"
  type    = "metric alert"
  message = <<-EOT
    Error rate above 5% on orders-service.
    Runbook: https://wiki.internal/runbooks/orders-high-error-rate
    @pagerduty-platform @slack-platform-alerts
  EOT

  query = <<-EOQ
    sum(last_5m):
      sum:trace.web.request.errors{service:orders-service,env:production}.as_count()
      / sum:trace.web.request.hits{service:orders-service,env:production}.as_count()
    > 0.05
  EOQ

  monitor_thresholds {
    critical = 0.05
    warning  = 0.02
  }

  tags = ["service:orders-service", "env:production", "team:platform"]

  notify_no_data    = true
  no_data_timeframe = 10
  renotify_interval = 30
}

# ---------------------------------------------------------------------------
# p99 Latency Monitor
# ---------------------------------------------------------------------------
resource "datadog_monitor" "orders_latency" {
  name    = "orders-service p99 latency high"
  type    = "metric alert"
  message = <<-EOT
    p99 latency above 1s on orders-service.
    Runbook: https://wiki.internal/runbooks/orders-high-latency
    @slack-platform-alerts
  EOT

  query = "p99(last_5m):trace.web.request{service:orders-service,env:production} > 1"

  monitor_thresholds {
    critical = 1.0
    warning  = 0.5
  }

  tags = ["service:orders-service", "env:production", "team:platform"]

  notify_no_data    = true
  no_data_timeframe = 10
}

# ---------------------------------------------------------------------------
# SLO — 99.9% Availability over 30 days
# ---------------------------------------------------------------------------
resource "datadog_service_level_objective" "orders_availability" {
  name        = "Orders Service Availability"
  type        = "metric"
  description = "99.9% of requests succeed over a rolling 30-day window"

  query {
    numerator   = "sum:trace.web.request.hits{service:orders-service,env:production,!status:error}.as_count()"
    denominator = "sum:trace.web.request.hits{service:orders-service,env:production}.as_count()"
  }

  thresholds {
    timeframe = "30d"
    target    = 99.9
    warning   = 99.95
  }

  tags = ["service:orders-service", "env:production", "team:platform"]
}
