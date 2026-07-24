# DESIGNED TO FAIL — proves bond_interface.devices validator SizeBetween(1, 8) rejects an empty
# list (size 0 < 1). Run via verify.sh (not plain terraform test). mock_provider => no credentials;
# validator fires from the real v3.76.0 schema at plan. interface_arm=bond renders the bond arm.
mock_provider "xcsh" {}

run "reject_bond_devices_empty" {
  command = plan

  variables {
    probe_name    = "cov-probe-s3-bond-empty"
    interface_arm = "bond"
    bond_devices  = []
  }
}
