# Azure Marketplace agreement for the sole Customer Edge image accepted by this
# configuration.  The agreement identity is deliberately fixed: callers cannot
# substitute a publisher, offer, or plan through an input variable.
locals {
  f5xc_customer_edge_marketplace_agreement_name = "f5-networks/offers/f5xc_customer_edge/plans/f5xc-ce-crt-20260201"
  f5xc_customer_edge_marketplace_agreement_id   = "/subscriptions/${var.subscription_id}/providers/Microsoft.MarketplaceOrdering/agreements/${local.f5xc_customer_edge_marketplace_agreement_name}"
}

# Read the exact subscription agreement first. Azure exposes this object even
# when its accepted property is false, which makes the subsequent PUT naturally
# idempotent and keeps agreement acceptance inside Terraform apply.
data "azapi_resource_action" "f5xc_customer_edge_marketplace_agreement" {
  type        = "Microsoft.MarketplaceOrdering/agreements/offers/plans@2021-01-01"
  resource_id = local.f5xc_customer_edge_marketplace_agreement_id
  action      = ""
  method      = "GET"

  response_export_values = ["*"]
}

resource "azapi_resource" "f5xc_customer_edge_marketplace_agreement" {
  type      = "Microsoft.MarketplaceOrdering/agreements/offers/plans@2021-01-01"
  parent_id = "/subscriptions/${var.subscription_id}/providers/Microsoft.MarketplaceOrdering/agreements/f5-networks/offers/f5xc_customer_edge"
  name      = "f5xc-ce-crt-20260201"

  # AzAPI 2.12.0 does not embed the Marketplace Ordering schema. The ARM API
  # version and fixed resource identity remain explicit and are validated by
  # the agreement GET plus Terraform tests below.
  schema_validation_enabled = false

  body = {
    properties = {
      accepted = true
    }
  }

  depends_on = [data.azapi_resource_action.f5xc_customer_edge_marketplace_agreement]
}
