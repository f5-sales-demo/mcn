# DESIGNED TO FAIL — proves software_settings.os.operating_system_version validator
# LengthAtMost(20) rejects a 21-char string. Run via verify.sh (not plain terraform test).
# mock_provider => no credentials; validator fires from the real provider schema at plan.
# os_arm=operating_system_version renders the pinned-version leaf so it is reachable.
mock_provider "xcsh" {}

run "reject_os_version_too_long" {
  command = plan

  variables {
    probe_name = "cov-probe-s5-os-bad"
    os_arm     = "operating_system_version"
    os_version = "123456789012345678901" # 21 chars > LengthAtMost(20)
  }
}
