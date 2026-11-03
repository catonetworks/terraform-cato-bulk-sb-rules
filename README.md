# terraform-cato-bulk-sb-rules

Bulk-manages the Cato **Socket Bypass (socketBypass)** policy from a single
JSON export: sections and rules (flat policy - no sub-policies exist for this
type), with ordering and publishing via `cato_bulk_sb_move_rule`.

## Resources managed

| Resource | Keyed by | Notes |
|---|---|---|
| `cato_socket_bypass_section.sections` | `section_name` | created `LAST_IN_POLICY`; ordered by the move resource |
| `cato_socket_bypass_rule.rules` | rule name | placement: managed section -> `LAST_IN_SECTION`; sectionless -> `LAST_IN_POLICY` |
| `cato_bulk_sb_move_rule.all_sb_rules` | - | orders sections (`section_index`) and rules (`index_in_section`) and **publishes** |
| `cato_socket_bypass_policy.policy` | - | optional account-level enable/disable toggle (`policy_enabled` variable) |

**Publishing:** the rule/section resources save to the draft policy only -
`cato_bulk_sb_move_rule` is this stack's single publisher. The API also offers
`reorderPolicy` for this family; the sequential mover is used for parity
with the other bulk stacks.

## Input JSON

```bash
catocli export sb_rules --json-filename all_sb_rules_and_sections.json
```

Root: `data.policy.socketBypass.policy` with `sections[]`, `rules[]`
(wrappers `{audit, rule, properties}`, ids retained for brownfield import),
and `rules_in_sections[]`. Rule fields: action (egress port + event), site scope, source/destination selectors (incl. vlan), simple/custom services, nested exceptions.

## Usage

```hcl
module "sb_rules" {
  source                   = "catonetworks/bulk-sb-rules/cato"
  sb_rules_json_file_path = "${path.module}/config_data/all_sb_rules_and_sections.json"
}
```

## Brownfield import

```bash
catocli import sb_rules_to_tf config_data/all_sb_rules_and_sections.json \
  --module-name module.sb_rules --auto-approve
terraform plan   # expect: only cato_bulk_sb_move_rule to add
```

## Known limitations

- Ordering rows with `section_name: ""` are excluded from the move resource
  and surfaced via `unordered_rules`; their order is creation order.
- Run applies with `-parallelism=1` when several module instances share an
  account.
