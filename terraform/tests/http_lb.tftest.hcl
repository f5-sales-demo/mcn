# Root plan test focused on the HTTP load balancer data-plane: the VIP is
# advertised per CE site (advertise_custom) and the LB serves the configured
# domain and default route pool. Mocks all providers (no credentials).

mock_provider "azurerm" {}
mock_provider "azuread" {}
mock_provider "xcsh" {}

variables {
  deployer = "tester"
  # enable_bgp=false: work around the provider 63-char object-ref name cap (see
  # main.tf). The LB/advertise/origin-pool under test are independent of bgp.
  enable_bgp     = false
  ssh_public_key = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIKzwDqvgRGHaZqbo57o/AxuuqRNPT9MqeYNYsK1Owh8l plan-test-only"
  # Pinned rather than inherited: `terraform test` also reads the gitignored
  # terraform.tfvars, so an assertion against a hard-coded namespace literal would
  # pass in CI and fail for any engineer whose app namespace differs.
  xc_app_namespace = "multi-cloud-networking"
}

run "loadbalancer_advertise_and_pool" {
  command = plan

  variables {
    ce_count = 3
  }

  # The dynamic advertise_where block (one entry per CE site) is exercised by
  # this run planning cleanly at N=3 — an expansion error would fail the run.

  assert {
    condition     = xcsh_http_loadbalancer.this.namespace == var.xc_app_namespace
    error_message = "LB must live in the app namespace named by xc_app_namespace."
  }

  assert {
    condition     = length(xcsh_http_loadbalancer.this.domains) == 1 && contains(xcsh_http_loadbalancer.this.domains, "ar-bgp-ecmp.bankexample.com")
    error_message = "LB should serve exactly ar-bgp-ecmp.bankexample.com."
  }

  assert {
    condition     = xcsh_origin_pool.this.namespace == var.xc_app_namespace
    error_message = "Origin pool must live in the app namespace named by xc_app_namespace."
  }

  assert {
    condition     = xcsh_origin_pool.this.port == 80
    error_message = "Origin pool port should be 80."
  }
}

# The app namespace is read, never owned (#634, #637): a managed xcsh_namespace
# resource would put a namespace this stack cannot recreate — and every unrelated
# object living in it — on the destroy list. Sourcing the pool/LB namespace from
# the data source is what keeps it off that list, so assert the wiring: these
# references stop resolving the moment anyone reintroduces the resource.
run "app_namespace_is_read_not_owned" {
  command = plan

  variables {
    ce_count = 1
  }

  assert {
    condition     = data.xcsh_namespace.mcn.name == var.xc_app_namespace
    error_message = "The app namespace must be looked up by the xc_app_namespace input."
  }

  # A namespace object is not itself contained in a namespace; the API reports
  # metadata.namespace as "" for one, so the lookup must ask for exactly that.
  assert {
    condition     = data.xcsh_namespace.mcn.namespace == ""
    error_message = "The namespace lookup must use an empty containing namespace."
  }

  assert {
    condition     = xcsh_origin_pool.this.namespace == data.xcsh_namespace.mcn.name
    error_message = "The origin pool must take its namespace from the data source, not a bare variable."
  }

  assert {
    condition     = xcsh_http_loadbalancer.this.namespace == data.xcsh_namespace.mcn.name
    error_message = "The LB must take its namespace from the data source, not a bare variable."
  }

  # Written as a for-expression because `terraform test` accepts only attribute
  # traversals in a reference, never an index step.
  assert {
    condition = alltrue([
      for route_pool in xcsh_http_loadbalancer.this.default_route_pools :
      route_pool.pool.namespace == data.xcsh_namespace.mcn.name
    ])
    error_message = "The default route pool reference must resolve through the data source."
  }
}
