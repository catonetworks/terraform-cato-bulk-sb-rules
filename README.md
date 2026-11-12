# terraform-cato-bulk-sb-rules

Bulk-manages the Cato **Socket Bypass (socketBypass)** policy from a single
JSON export: sections and rules (flat policy - no sub-policies exist for this
type), with ordering and publishing via `cato_bulk_sb_move_rule`.

## Usage

### Basic Example

```hcl
module "sb_rules" {
  source                   = "catonetworks/bulk-sb-rules/cato"
  sb_rules_json_file_path = "${path.module}/config_data/all_sb_rules_and_sections.json"
}
```

### JSON Configuration Structure

```bash
catocli export sb_rules --json-filename all_sb_rules_and_sections.json
```

Root: `data.policy.socketBypass.policy` with `sections[]`, `rules[]`
(wrappers `{audit, rule, properties}`, ids retained for brownfield import),
and `rules_in_sections[]`.

#### Key Fields:

- **`sections[]`**: `section_index` (order) and `section_name`.
- **`rules[]`**: each entry is a `{audit, rule, properties}` wrapper; the
  `rule` body carries action (egress port + event), site scope,
  source/destination selectors (including vlan), simple/custom services, and
  nested exceptions.
- **`rules_in_sections[]`**: maps each rule to a section with
  `index_in_section`, `section_name`, and `rule_name`.

#### Resources Managed

| Resource | Keyed by | Notes |
|---|---|---|
| `cato_socket_bypass_section.sections` | `section_name` | created `LAST_IN_POLICY`; ordered by the move resource |
| `cato_socket_bypass_rule.rules` | rule name | placement: managed section -> `LAST_IN_SECTION`; sectionless -> `LAST_IN_POLICY` |
| `cato_bulk_sb_move_rule.all_sb_rules` | - | orders sections (`section_index`) and rules (`index_in_section`) and **publishes** |
| `cato_socket_bypass_policy.policy` | - | optional account-level enable/disable toggle (`policy_enabled` variable) |
| `terraform_data.guard_empty_policy` | - | safety guard: fails `plan` if the JSON has 0 rules, unless `allow_empty_policy = true` |

**Publishing:** the rule/section resources save to the draft policy only -
`cato_bulk_sb_move_rule` is this stack's single publisher. The API also offers
`reorderPolicy` for this family; the sequential mover is used for parity
with the other bulk stacks.

### How Rule Ordering Works

`rules_in_sections[]` is what actually drives ordering, not the position of
entries in `sections[]`/`rules[]`. Each row's `section_index` (from the
owning section) and `index_in_section` tell `cato_bulk_sb_move_rule` where to
place that section and rule when it runs - and that same resource both
applies the ordering and republishes the policy on every apply. Rows with
`section_name: ""` have no managed section to order within, so they're
excluded from the move resource; their effective order is creation order,
and they're surfaced separately via the `unordered_rules` output.

### Parameters

- `sb_rules_json_file_path` - path to the Socket Bypass JSON export produced
  by `catocli export sb_rules`.
- `policy_enabled` - manages the account-level Socket Bypass policy toggle.
  `null` (default) leaves the toggle unmanaged; `true`/`false` manages it via
  `cato_socket_bypass_policy`.
- `allow_empty_policy` - safety guard (default `false`); fails `plan` if the
  JSON has 0 rules unless explicitly set `true`.

## Working with Existing Rules (Brownfield Deployments)

### Installing and Configuring Cato CLI

1. **Install the Cato CLI:**
   ```bash
   pip3 install catocli
   ```

2. **Configure the CLI with your Cato credentials:**
   ```bash
   catocli configure set
   ```
   This will prompt you for your Cato Management Application credentials and account information.

### Exporting Existing Rules

To export your existing Socket Bypass rules and sections into the JSON format required by this module:

```bash
catocli export sb_rules --json-filename all_sb_rules_and_sections.json
```

### Importing Existing Rules into Terraform State (native import blocks)

Requires Terraform **>= 1.7**. Every `for_each` address in this module
(`rules_by_name`, `sections_data`) is keyed by name, exactly matching the
exported JSON's `rule.name` / `section_name` fields - that's why the import
blocks below line up one-to-one with the JSON with no re-keying.

<details>
<summary>Option A (recommended) - native Terraform import blocks (migration.tf)</summary>

```hcl
# migration.tf - one-time adoption of existing Socket Bypass rules/sections.
# Place beside the module call (same directory as main.tf), run once, then delete.

locals {
  sb_migration_json     = jsondecode(file("${path.module}/config_data/all_sb_rules_and_sections.json"))
  sb_migration_policy   = local.sb_migration_json.data.policy.socketBypass.policy
  sb_migration_sections = { for s in local.sb_migration_policy.sections : s.section_name => s.section_id }
  sb_migration_rules    = { for rw in local.sb_migration_policy.rules : rw.rule.name => rw.rule.id }
}

import {
  for_each = local.sb_migration_sections
  to       = module.sb_rules.cato_socket_bypass_section.sections[each.key]
  id       = each.value
}

import {
  for_each = local.sb_migration_rules
  to       = module.sb_rules.cato_socket_bypass_rule.rules[each.key]
  id       = each.value
}
```

`cato_bulk_sb_move_rule` is plan-time orchestration - it republishes the
whole policy on every apply and has no persisted object of its own to
import, so it never appears in `migration.tf`. Same for the optional
`cato_socket_bypass_policy` enable/disable toggle: it's a tenant-wide
singleton with no name/`for_each` to key an import block on.

</details>

<details>
<summary>Option B - catocli import sb_rules_to_tf (imperative alternative)</summary>

```bash
catocli import sb_rules_to_tf config_data/all_sb_rules_and_sections.json \
  --module-name module.sb_rules --auto-approve
terraform plan   # expect: only cato_bulk_sb_move_rule to add
```

This mutates Terraform state immediately - there's no plan preview before
the import happens. Use it only when Option A isn't practical (e.g.
Terraform < 1.7).

</details>

### Typical Brownfield Workflow

1. Export: `catocli export sb_rules --json-filename all_sb_rules_and_sections.json`
2. Write `migration.tf` beside the module call, as in Option A above.
3. Preview: `terraform plan` - expect `N to import, 0 to add, 0 to change, 0
   to destroy`. Any planned **change** (not just import) means the JSON is
   stale relative to the live policy - re-export and regenerate
   `migration.tf` before applying; never let `terraform apply` overwrite the
   live policy from an old backup.
4. Adopt: `terraform apply`.
5. Delete `migration.tf` - it's a one-time migration aid, not steady-state
   config.

Option B (`catocli import sb_rules_to_tf`) is the alternative when Option A
isn't practical.

### Backup and Restore Workflow

If unintended changes are made directly to rules or sections in the Cato
Management Application, you can restore to the last known good state:

1. **Apply your last known good configuration:**
   ```bash
   terraform apply
   ```
   This restores rules and sections to match your Terraform configuration
   and republishes via `cato_bulk_sb_move_rule`.
2. **Alternatively, re-export and compare:**
   ```bash
   catocli export sb_rules --json-filename all_sb_rules_and_sections.json
   # Compare with your existing JSON file to identify drift
   ```

## Using Module Outputs

```hcl
output "sb_deployment_info" {
  description = "Basic information about the Socket Bypass deployment"
  value = {
    sections   = module.sb_rules.deployment_summary.sections
    rules      = module.sb_rules.deployment_summary.rules
    section_ids = module.sb_rules.section_ids
    rule_ids    = module.sb_rules.rule_ids
  }
}

output "sb_unordered_rules" {
  description = "Rules not covered by the move resource (no managed section to order within)"
  value       = module.sb_rules.unordered_rules
}
```

### Output Use Cases

- **`deployment_summary`**: quick counts of managed sections/rules, useful for dashboards or drift checks.
- **`section_ids`**: map of section name to id, for referencing sections from other modules or import blocks.
- **`rule_ids`**: map of rule name to id, for referencing rules from other modules or import blocks.
- **`unordered_rules`**: informational list of `rules_in_sections` rows excluded from `cato_bulk_sb_move_rule` - review these to confirm their creation-order placement is acceptable.

## Known limitations

- `allow_empty_policy` (default `false`) guards against a truncated or
  wrong-tenant export destroying the live policy - see Parameters above.
- Ordering rows with `section_name: ""` are excluded from the move resource
  and surfaced via `unordered_rules`; their order is creation order.
- Run applies with `-parallelism=1` when several module instances share an
  account.
- Only `cato_socket_bypass_rule`/`cato_socket_bypass_section` support
  import; `cato_bulk_sb_move_rule` and the `cato_socket_bypass_policy`
  toggle are outside the JSON-driven import flow (see above).

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
|------|---------|
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.5.0 |
| <a name="requirement_cato"></a> [cato](#requirement\_cato) | >= 1.3.1 |

## Providers

| Name | Version |
|------|---------|
| <a name="provider_cato"></a> [cato](#provider\_cato) | >= 1.3.1 |
| <a name="provider_terraform"></a> [terraform](#provider\_terraform) | n/a |

## Modules

No modules.

## Resources

| Name | Type |
|------|------|
| [cato_bulk_sb_move_rule.all_sb_rules](https://registry.terraform.io/providers/catonetworks/cato/latest/docs/resources/bulk_sb_move_rule) | resource |
| [cato_socket_bypass_policy.policy](https://registry.terraform.io/providers/catonetworks/cato/latest/docs/resources/socket_bypass_policy) | resource |
| [cato_socket_bypass_rule.rules](https://registry.terraform.io/providers/catonetworks/cato/latest/docs/resources/socket_bypass_rule) | resource |
| [cato_socket_bypass_section.sections](https://registry.terraform.io/providers/catonetworks/cato/latest/docs/resources/socket_bypass_section) | resource |
| [terraform_data.guard_empty_policy](https://registry.terraform.io/providers/hashicorp/terraform/latest/docs/resources/data) | resource |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_allow_empty_policy"></a> [allow\_empty\_policy](#input\_allow\_empty\_policy) | Safety guard: fail planning when the policy JSON contains 0 rules unless explicitly allowed. Protects against a truncated or wrong-tenant export destroying the live policy. Set true only for intentional greenfield/teardown. | `bool` | `false` | no |
| <a name="input_policy_enabled"></a> [policy\_enabled](#input\_policy\_enabled) | Manage the account-level Socket Bypass policy toggle. null leaves the toggle unmanaged; true/false manages it via cato\_socket\_bypass\_policy. | `bool` | `null` | no |
| <a name="input_sb_rules_json_file_path"></a> [sb\_rules\_json\_file\_path](#input\_sb\_rules\_json\_file\_path) | Path to the Socket Bypass JSON export produced by `catocli export sb_rules` (data.policy.socketBypass.policy root). | `string` | n/a | yes |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_deployment_summary"></a> [deployment\_summary](#output\_deployment\_summary) | Counts of managed Socket Bypass objects. |
| <a name="output_rule_ids"></a> [rule\_ids](#output\_rule\_ids) | Map of rule name to rule id. |
| <a name="output_section_ids"></a> [section\_ids](#output\_section\_ids) | Map of section name to section id. |
| <a name="output_unordered_rules"></a> [unordered\_rules](#output\_unordered\_rules) | rules\_in\_sections rows excluded from cato\_bulk\_sb\_move\_rule (no managed section to order within). |
<!-- END_TF_DOCS -->
