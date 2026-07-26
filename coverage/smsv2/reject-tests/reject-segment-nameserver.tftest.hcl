# DESIGNED TO FAIL — proves segment_vrf.segment_config.nameserver validator IPv4Validator() rejects
# a malformed IPv4. Run via verify.sh (not plain terraform test). mock_provider => no credentials;
# validator fires from the real provider schema at plan. segment_vrf_arm=inline renders the
# segment_config so the nameserver leaf is reachable. The malformed value ("300.2.2.2") differs from
# the S2 local_vrf nameserver reject ("300.1.1.1") so its diagnostic is unambiguous. segment_nameserver
# has no terraform validation so the provider IPv4 validator fires.
mock_provider "xcsh" {}

run "reject_segment_nameserver_bad_ipv4" {
  command = plan

  variables {
    probe_name         = "cov-probe-s4-segns-bad"
    segment_vrf_arm    = "inline"
    segment_nameserver = "300.2.2.2"
  }
}
