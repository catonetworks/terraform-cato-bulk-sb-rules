variable "sb_rules_json_file_path" {
  description = "Path to the Socket Bypass JSON export produced by `catocli export sb_rules` (data.policy.socketBypass.policy root)."
  type        = string
}

variable "policy_enabled" {
  description = "Manage the account-level Socket Bypass policy toggle. null leaves the toggle unmanaged; true/false manages it via cato_socket_bypass_policy."
  type        = bool
  default     = null
}
