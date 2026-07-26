# DESIGNED TO FAIL — proves re_select.specific_re.primary_re validator LengthBetween(1, 64) rejects a
# 65-char string (> max). Run via verify.sh (not plain terraform test). mock_provider => no
# credentials; validator fires from the real provider schema at plan. re_select_arm=specific_re renders
# the specific_re leaves so primary_re is reachable.
mock_provider "xcsh" {}

run "reject_primary_re_too_long" {
  command = plan

  variables {
    probe_name    = "cov-probe-s5-primary-re-bad"
    re_select_arm = "specific_re"
    primary_re    = "12345678901234567890123456789012345678901234567890123456789012345" # 65 chars > LengthBetween(1, 64)
  }
}
