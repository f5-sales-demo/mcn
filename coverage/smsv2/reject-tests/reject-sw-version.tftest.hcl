# DESIGNED TO FAIL — proves software_settings.sw.volterra_software_version validator
# LengthAtMost(20) rejects a 21-char string. Run via verify.sh (not plain terraform test).
# mock_provider => no credentials; validator fires from the real provider schema at plan.
# sw_arm=volterra_software_version renders the pinned-version leaf so it is reachable.
mock_provider "xcsh" {}

run "reject_sw_version_too_long" {
  command = plan

  variables {
    probe_name = "cov-probe-s5-sw-bad"
    sw_arm     = "volterra_software_version"
    sw_version = "123456789012345678901" # 21 chars > LengthAtMost(20)
  }
}
