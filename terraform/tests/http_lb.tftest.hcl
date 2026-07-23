# Root plan test focused on the HTTP load balancer data-plane: the VIP is
# advertised per CE site (advertise_custom) and the LB serves the configured
# domain and default route pool. Mocks all providers (no credentials).

mock_provider "azurerm" {}
mock_provider "azuread" {}
mock_provider "xcsh" {}

run "loadbalancer_advertise_and_pool" {
  command = plan

  variables {
    ce_count = 3
    deployer = "tester"
    # enable_bgp=false: work around the provider 63-char object-ref name cap (see
    # main.tf). The LB/advertise/origin-pool under test are independent of bgp.
    enable_bgp     = false
    ssh_public_key = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIKzwDqvgRGHaZqbo57o/AxuuqRNPT9MqeYNYsK1Owh8l plan-test-only"
  }

  # The dynamic advertise_where block (one entry per CE site) is exercised by
  # this run planning cleanly at N=3 — an expansion error would fail the run.

  assert {
    condition     = xcsh_http_loadbalancer.this.namespace == "r-mordasiewicz"
    error_message = "LB must live in the app namespace r-mordasiewicz."
  }

  assert {
    condition     = length(xcsh_http_loadbalancer.this.domains) == 1 && contains(xcsh_http_loadbalancer.this.domains, "ar-bgp-ecmp.bankexample.com")
    error_message = "LB should serve exactly ar-bgp-ecmp.bankexample.com."
  }

  assert {
    condition     = xcsh_origin_pool.this.namespace == "r-mordasiewicz"
    error_message = "Origin pool must live in the app namespace r-mordasiewicz."
  }

  assert {
    condition     = xcsh_origin_pool.this.port == 80
    error_message = "Origin pool port should be 80."
  }
}
