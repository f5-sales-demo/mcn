# Root plan test for the provider-generated CE registration token. Mocks all
# three providers so the graph plans with no Azure or XC credentials. Proves the
# xcsh_token.ce resource is planned and that the CE cloud-init token feed
# resolves to xcsh_token.ce.uid by default, while an explicit
# var.registration_token still overrides it.

mock_provider "azurerm" {}
mock_provider "azuread" {}
mock_provider "xcsh" {}

# Default (registration_token = ""): the generated token is used.
run "generated_token_is_used" {
  command = plan

  variables {
    ce_count       = 1
    deployer       = "tester"
    enable_bgp     = false
    ssh_public_key = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIKzwDqvgRGHaZqbo57o/AxuuqRNPT9MqeYNYsK1Owh8l plan-test-only"
  }

  # The xcsh_token.ce resource is planned with the expected metadata.
  assert {
    condition     = xcsh_token.ce.name == "mcn-ce-registration"
    error_message = "The CE registration token resource must be named mcn-ce-registration."
  }

  assert {
    condition     = xcsh_token.ce.namespace == "system"
    error_message = "The CE registration token must live in the system namespace."
  }

  # No override => the cloud-init feed selects the generated xcsh_token.ce.uid.
  assert {
    condition     = output.registration_token_is_generated == true
    error_message = "With registration_token empty, the token feed must use the generated xcsh_token.ce.uid."
  }
}

# Explicit override: var.registration_token wins over the generated token.
run "override_token_wins" {
  command = plan

  variables {
    ce_count           = 1
    deployer           = "tester"
    enable_bgp         = false
    registration_token = "externally-minted-token-abc123"
    ssh_public_key     = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIKzwDqvgRGHaZqbo57o/AxuuqRNPT9MqeYNYsK1Owh8l plan-test-only"
  }

  assert {
    condition     = output.registration_token_is_generated == false
    error_message = "A non-empty registration_token must override the generated token feed."
  }

  # The resolved token fed to cloud-init equals the supplied override.
  assert {
    condition     = output.ce_registration_token == "externally-minted-token-abc123"
    error_message = "The cloud-init token feed must resolve to the var.registration_token override."
  }
}
