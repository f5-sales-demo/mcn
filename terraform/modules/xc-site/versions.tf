terraform {
  required_version = ">= 1.8"

  required_providers {
    xcsh = {
      source = "f5-sales-demo/xcsh"
      # >= 3.74.0: the object-ref name validator relaxed 63 -> 128 chars, so the
      # real 71-char auto-derived SLO interface name the BGP peer binds to now
      # validates (the xcsh_bgp binding below is no longer length-gated).
      version = ">= 3.74.0"
    }
  }
}
