# TGW Connect cannot reach the AWS provider until the external release proof and
# live operational telemetry both publish the same supported schema.

data "external" "smsv2_contract" {
  count = var.enable_aws_tgw_connect ? 1 : 0

  program = ["${path.module}/scripts/verify-smsv2-contract.sh"]
  query = {
    release = var.smsv2_contract_release
  }
}

data "external" "smsv2_runtime_telemetry" {
  count = var.enable_aws_tgw_connect ? 1 : 0

  program = ["${path.module}/scripts/read-smsv2-runtime-telemetry.sh"]
  query = {
    release                  = data.external.smsv2_contract[0].result.release_tag
    telemetry_schema_version = data.external.smsv2_contract[0].result.telemetry_schema_version
  }
}

resource "terraform_data" "aws_tgw_connect_gate" {
  count = var.enable_aws_tgw_connect ? 1 : 0

  input = merge(
    data.external.smsv2_contract[0].result,
    { runtime_available = data.external.smsv2_runtime_telemetry[0].result.available },
  )

  lifecycle {
    precondition {
      condition     = data.external.smsv2_contract[0].result.verified == "true" && data.external.smsv2_contract[0].result.tgw_connect == "available" && data.external.smsv2_contract[0].result.runtime_status == "available" && data.external.smsv2_contract[0].result.telemetry_schema_version != "unavailable" && data.external.smsv2_runtime_telemetry[0].result.available == "true" && data.external.smsv2_runtime_telemetry[0].result.release_tag == data.external.smsv2_contract[0].result.release_tag && data.external.smsv2_runtime_telemetry[0].result.schema_version == data.external.smsv2_contract[0].result.telemetry_schema_version
      error_message = "AWS TGW Connect is unavailable: both the verified SMSv2 release and a matching authenticated runtime telemetry response must attest the same supported schema before Terraform can plan AWS mutations."
    }
  }
}

output "aws_tgw_connect_capability" {
  description = "Verified SMSv2 capability result for an AWS TGW Connect request; no runtime value is inferred."
  value = var.enable_aws_tgw_connect ? {
    release_tag              = data.external.smsv2_contract[0].result.release_tag
    release_commit           = data.external.smsv2_contract[0].result.release_commit
    telemetry_schema_version = data.external.smsv2_contract[0].result.telemetry_schema_version
    runtime_status           = data.external.smsv2_contract[0].result.runtime_status
    runtime_available        = data.external.smsv2_runtime_telemetry[0].result.available
    runtime_reason           = data.external.smsv2_runtime_telemetry[0].result.reason
    tgw_connect              = data.external.smsv2_contract[0].result.tgw_connect
    } : {
    release_tag              = null
    release_commit           = null
    telemetry_schema_version = "not-requested"
    runtime_status           = "not-requested"
    runtime_available        = "not-requested"
    runtime_reason           = "not-requested"
    tgw_connect              = "not-requested"
  }
}
