# DESIGNED TO FAIL — proves admin_user_credentials.ssh_key validator LengthAtMost(8192) rejects a
# >8192-char string. Run via verify.sh (not plain terraform test). mock_provider => no credentials;
# validator fires from the real provider schema at plan. admin_creds=true renders the block; the
# 8200-char key is generated in-HCL (join+range over 10-char chunks; `range` caps at 1024 elements) so
# no oversized literal is committed.
mock_provider "xcsh" {}

run "reject_ssh_key_too_long" {
  command = plan

  variables {
    probe_name  = "cov-probe-s5-ssh-key-bad"
    admin_creds = true
    ssh_key     = join("", [for _ in range(820) : "0123456789"]) # 8200 chars > LengthAtMost(8192)
  }
}
