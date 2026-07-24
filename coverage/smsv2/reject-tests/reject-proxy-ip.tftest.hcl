# DESIGNED TO FAIL — proves custom_proxy.proxy_ip_address validator IPv4Validator() rejects a
# malformed IPv4. Run via verify.sh (not plain terraform test). mock_provider => no credentials;
# validator fires from the real v3.76.0 schema at plan. proxy_arm=custom_proxy (default) + the
# default extended_arms=true render custom_proxy so the proxy_ip_address leaf is reachable. The
# malformed value differs from the S2 static_ip reject ("999.999.0.0/8") so its diagnostic is
# unambiguous. proxy_ip_address has no terraform validation so the provider IPv4 validator fires.
mock_provider "xcsh" {}

run "reject_proxy_ip_bad_ipv4" {
  command = plan

  variables {
    probe_name       = "cov-probe-s4-proxyip-bad"
    proxy_ip_address = "999.1.1.1"
  }
}
