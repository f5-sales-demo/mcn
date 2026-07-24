# DESIGNED TO FAIL — proves admin_user_credentials.admin_password.secret_encoding_type validator
# OneOf(EncodingNone, EncodingBase64) rejects an out-of-enum value. Run via verify.sh (not plain
# terraform test). mock_provider => no credentials; validator fires from the real v3.76.0 schema at
# plan. admin_creds=true renders the block; secret_encoding_type has no terraform validation so the
# provider OneOf validator fires.
mock_provider "xcsh" {}

run "reject_secret_encoding_out_of_enum" {
  command = plan

  variables {
    probe_name           = "cov-probe-s5-encoding-bad"
    admin_creds          = true
    secret_encoding_type = "BOGUS"
  }
}
