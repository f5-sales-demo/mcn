# DESIGNED TO FAIL — proves node_list[].type validator OneOf("Control", "Worker") rejects an
# out-of-enum value. Run via verify.sh (not plain terraform test). mock_provider => no credentials.
# The type leaf is always wired regardless of string_arms.
mock_provider "xcsh" {}

run "reject_node_type_out_of_enum" {
  command = plan

  variables {
    probe_name = "cov-probe-s2-type"
    node_type  = "Bogus"
  }
}
