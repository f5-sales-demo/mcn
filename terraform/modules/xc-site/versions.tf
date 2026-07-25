terraform {
  required_version = ">= 1.8"

  required_providers {
    xcsh = {
      source = "f5-sales-demo/xcsh"
      # This module declares the registration pair, so its floor must carry them:
      # >= 3.77.3 ships the xcsh_site_registration data source (resolves a CE's
      # r-<uuid> runtime registration name from its site name) alongside
      # xcsh_registration_approval. It also includes >= 3.74.0's object-ref name
      # validator relaxed 63 -> 128 chars, so the real 71-char auto-derived SLO
      # interface name the BGP peer binds to validates (xcsh_bgp is not
      # length-gated). >= 3.77.5 raises the floor to the two labels fixes this
      # module now relies on instead of `ignore_changes`: import-marker suppression
      # for the nested interface_list `labels {}` block (#1244) and preservation of
      # a config-declared empty top-level metadata `labels` map (#1286).
      # Keep in lock-step with the root terraform/versions.tf.
      version = ">= 3.77.5"
    }
  }
}
