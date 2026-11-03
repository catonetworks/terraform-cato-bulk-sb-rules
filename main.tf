# terraform-cato-bulk-sb-rules
#
# Bulk-manages the Cato Socket Bypass (socketBypass) policy from one JSON
# export produced by `catocli export sb_rules`:
#   sections[] / rules[] / rules_in_sections[] - flat policy, no sub-policies.
# cato_bulk_sb_move_rule applies ordering and republishes.
# Rule fields: action (egress port + event), site scope, source/destination selectors (incl. vlan), simple/custom services, nested exceptions.

locals {
  sb_json = jsondecode(file("${var.sb_rules_json_file_path}"))
  sb      = local.sb_json.data.policy.socketBypass.policy

  sections_data_raw      = try(local.sb.sections, [])
  rules_data_raw         = try(local.sb.rules, [])
  rules_in_sections_data = try(local.sb.rules_in_sections, [])

  sections_data = {
    for s in local.sections_data_raw : s.section_name => s
  }

  rules_by_name = {
    for rw in local.rules_data_raw : rw.rule.name => rw
  }

  move_section_data = {
    for name, s in local.sections_data : name => {
      section_index = s.section_index
    }
  }

  move_rule_data = {
    for row in local.rules_in_sections_data :
    row.rule_name => {
      index_in_section = row.index_in_section
      section_name     = row.section_name
    }
    if row.section_name != "" && contains(keys(local.sections_data), row.section_name)
  }

  unordered_rules_data = [
    for row in local.rules_in_sections_data : row
    if !contains(keys(local.move_rule_data), try(row.rule_name, ""))
  ]

  rule_bodies = {
    for name, rw in local.rules_by_name : name => merge(
      {
        name    = rw.rule.name
        enabled = try(rw.rule.enabled, true)
      },
      try(rw.rule.description, "") != "" ? { description = rw.rule.description } : {},
      try(rw.rule.action, null) != null ? {
        action = {
          port          = try(rw.rule.action.port, "AUTOMATIC")
          event_enabled = try(rw.rule.action.event.enabled, false)
        }
      } : {},
      merge(
        try(length(rw.rule.site.site), 0) > 0 || try(length(rw.rule.site.group), 0) > 0 ? {
          site = merge(
            try(length(rw.rule.site.site), 0) > 0 ? { site = [for x in rw.rule.site.site : can(x.name) ? { name = x.name } : { id = x.id }] } : {},
            try(length(rw.rule.site.group), 0) > 0 ? { group = [for x in rw.rule.site.group : can(x.name) ? { name = x.name } : { id = x.id }] } : {}
          )
        } : {},
        anytrue([
          try(length(rw.rule.source.floatingSubnet), 0) > 0,
          try(length(rw.rule.source.globalIpRange), 0) > 0,
          try(length(rw.rule.source.group), 0) > 0,
          try(length(rw.rule.source.host), 0) > 0,
          try(length(rw.rule.source.ip), 0) > 0,
          try(length(rw.rule.source.ipRange), 0) > 0,
          try(length(rw.rule.source.networkInterface), 0) > 0,
          try(length(rw.rule.source.siteNetworkSubnet), 0) > 0,
          try(length(rw.rule.source.subnet), 0) > 0,
          try(length(rw.rule.source.vlan), 0) > 0,
          ]) ? {
          source = merge(
            try(length(rw.rule.source.floatingSubnet), 0) > 0 ? { floating_subnet = [for x in rw.rule.source.floatingSubnet : can(x.name) ? { name = x.name } : { id = x.id }] } : {},
            try(length(rw.rule.source.globalIpRange), 0) > 0 ? { global_ip_range = [for x in rw.rule.source.globalIpRange : can(x.name) ? { name = x.name } : { id = x.id }] } : {},
            try(length(rw.rule.source.group), 0) > 0 ? { group = [for x in rw.rule.source.group : can(x.name) ? { name = x.name } : { id = x.id }] } : {},
            try(length(rw.rule.source.host), 0) > 0 ? { host = [for x in rw.rule.source.host : can(x.name) ? { name = x.name } : { id = x.id }] } : {},
            try(length(rw.rule.source.ip), 0) > 0 ? { ip = rw.rule.source.ip } : {},
            try(length(rw.rule.source.ipRange), 0) > 0 ? { ip_range = [for r in rw.rule.source.ipRange : { from = r.from, to = r.to }] } : {},
            try(length(rw.rule.source.networkInterface), 0) > 0 ? { network_interface = [for x in rw.rule.source.networkInterface : can(x.name) ? { name = x.name } : { id = x.id }] } : {},
            try(length(rw.rule.source.siteNetworkSubnet), 0) > 0 ? { site_network_subnet = [for x in rw.rule.source.siteNetworkSubnet : can(x.name) ? { name = x.name } : { id = x.id }] } : {},
            try(length(rw.rule.source.subnet), 0) > 0 ? { subnet = rw.rule.source.subnet } : {},
            try(length(rw.rule.source.vlan), 0) > 0 ? { vlan = rw.rule.source.vlan } : {}
          )
        } : {},
        anytrue([
          try(length(rw.rule.destination.application), 0) > 0,
          try(length(rw.rule.destination.customApp), 0) > 0,
          try(length(rw.rule.destination.domain), 0) > 0,
          try(length(rw.rule.destination.fqdn), 0) > 0,
          try(length(rw.rule.destination.globalIpRange), 0) > 0,
          try(length(rw.rule.destination.ip), 0) > 0,
          try(length(rw.rule.destination.ipRange), 0) > 0,
          try(length(rw.rule.destination.subnet), 0) > 0,
          ]) ? {
          destination = merge(
            try(length(rw.rule.destination.application), 0) > 0 ? { application = [for x in rw.rule.destination.application : can(x.name) ? { name = x.name } : { id = x.id }] } : {},
            try(length(rw.rule.destination.customApp), 0) > 0 ? { custom_app = [for x in rw.rule.destination.customApp : can(x.name) ? { name = x.name } : { id = x.id }] } : {},
            try(length(rw.rule.destination.domain), 0) > 0 ? { domain = rw.rule.destination.domain } : {},
            try(length(rw.rule.destination.fqdn), 0) > 0 ? { fqdn = rw.rule.destination.fqdn } : {},
            try(length(rw.rule.destination.globalIpRange), 0) > 0 ? { global_ip_range = [for x in rw.rule.destination.globalIpRange : can(x.name) ? { name = x.name } : { id = x.id }] } : {},
            try(length(rw.rule.destination.ip), 0) > 0 ? { ip = rw.rule.destination.ip } : {},
            try(length(rw.rule.destination.ipRange), 0) > 0 ? { ip_range = [for r in rw.rule.destination.ipRange : { from = r.from, to = r.to }] } : {},
            try(length(rw.rule.destination.subnet), 0) > 0 ? { subnet = rw.rule.destination.subnet } : {}
          )
        } : {},
        try(length(rw.rule.service.simple), 0) > 0 || try(length(rw.rule.service.custom), 0) > 0 ? {
          service = merge(
            try(length(rw.rule.service.simple), 0) > 0 ? { simple = [for s in rw.rule.service.simple : s.name] } : {},
            try(length(rw.rule.service.custom), 0) > 0 ? {
              custom = [for c in rw.rule.service.custom : merge(
                { protocol = c.protocol },
                try(length(c.port), 0) > 0 ? { port = [for p in c.port : tostring(p)] } : {},
                try(c.portRange, null) != null ? { port_range = { from = tostring(c.portRange.from), to = tostring(c.portRange.to) } } : {}
              )]
            } : {}
          )
        } : {}
      ),
      try(length(rw.rule.exception), 0) > 0 ? {
        exception = [for ex in rw.rule.exception : merge(
          { name = ex.name },
          merge(
            try(length(ex.site.site), 0) > 0 || try(length(ex.site.group), 0) > 0 ? {
              site = merge(
                try(length(ex.site.site), 0) > 0 ? { site = [for x in ex.site.site : can(x.name) ? { name = x.name } : { id = x.id }] } : {},
                try(length(ex.site.group), 0) > 0 ? { group = [for x in ex.site.group : can(x.name) ? { name = x.name } : { id = x.id }] } : {}
              )
            } : {},
            anytrue([
              try(length(ex.source.floatingSubnet), 0) > 0,
              try(length(ex.source.globalIpRange), 0) > 0,
              try(length(ex.source.group), 0) > 0,
              try(length(ex.source.host), 0) > 0,
              try(length(ex.source.ip), 0) > 0,
              try(length(ex.source.ipRange), 0) > 0,
              try(length(ex.source.networkInterface), 0) > 0,
              try(length(ex.source.siteNetworkSubnet), 0) > 0,
              try(length(ex.source.subnet), 0) > 0,
              try(length(ex.source.vlan), 0) > 0,
              ]) ? {
              source = merge(
                try(length(ex.source.floatingSubnet), 0) > 0 ? { floating_subnet = [for x in ex.source.floatingSubnet : can(x.name) ? { name = x.name } : { id = x.id }] } : {},
                try(length(ex.source.globalIpRange), 0) > 0 ? { global_ip_range = [for x in ex.source.globalIpRange : can(x.name) ? { name = x.name } : { id = x.id }] } : {},
                try(length(ex.source.group), 0) > 0 ? { group = [for x in ex.source.group : can(x.name) ? { name = x.name } : { id = x.id }] } : {},
                try(length(ex.source.host), 0) > 0 ? { host = [for x in ex.source.host : can(x.name) ? { name = x.name } : { id = x.id }] } : {},
                try(length(ex.source.ip), 0) > 0 ? { ip = ex.source.ip } : {},
                try(length(ex.source.ipRange), 0) > 0 ? { ip_range = [for r in ex.source.ipRange : { from = r.from, to = r.to }] } : {},
                try(length(ex.source.networkInterface), 0) > 0 ? { network_interface = [for x in ex.source.networkInterface : can(x.name) ? { name = x.name } : { id = x.id }] } : {},
                try(length(ex.source.siteNetworkSubnet), 0) > 0 ? { site_network_subnet = [for x in ex.source.siteNetworkSubnet : can(x.name) ? { name = x.name } : { id = x.id }] } : {},
                try(length(ex.source.subnet), 0) > 0 ? { subnet = ex.source.subnet } : {},
                try(length(ex.source.vlan), 0) > 0 ? { vlan = ex.source.vlan } : {}
              )
            } : {},
            anytrue([
              try(length(ex.destination.application), 0) > 0,
              try(length(ex.destination.customApp), 0) > 0,
              try(length(ex.destination.domain), 0) > 0,
              try(length(ex.destination.fqdn), 0) > 0,
              try(length(ex.destination.globalIpRange), 0) > 0,
              try(length(ex.destination.ip), 0) > 0,
              try(length(ex.destination.ipRange), 0) > 0,
              try(length(ex.destination.subnet), 0) > 0,
              ]) ? {
              destination = merge(
                try(length(ex.destination.application), 0) > 0 ? { application = [for x in ex.destination.application : can(x.name) ? { name = x.name } : { id = x.id }] } : {},
                try(length(ex.destination.customApp), 0) > 0 ? { custom_app = [for x in ex.destination.customApp : can(x.name) ? { name = x.name } : { id = x.id }] } : {},
                try(length(ex.destination.domain), 0) > 0 ? { domain = ex.destination.domain } : {},
                try(length(ex.destination.fqdn), 0) > 0 ? { fqdn = ex.destination.fqdn } : {},
                try(length(ex.destination.globalIpRange), 0) > 0 ? { global_ip_range = [for x in ex.destination.globalIpRange : can(x.name) ? { name = x.name } : { id = x.id }] } : {},
                try(length(ex.destination.ip), 0) > 0 ? { ip = ex.destination.ip } : {},
                try(length(ex.destination.ipRange), 0) > 0 ? { ip_range = [for r in ex.destination.ipRange : { from = r.from, to = r.to }] } : {},
                try(length(ex.destination.subnet), 0) > 0 ? { subnet = ex.destination.subnet } : {}
              )
            } : {},
            try(length(ex.service.simple), 0) > 0 || try(length(ex.service.custom), 0) > 0 ? {
              service = merge(
                try(length(ex.service.simple), 0) > 0 ? { simple = [for s in ex.service.simple : s.name] } : {},
                try(length(ex.service.custom), 0) > 0 ? {
                  custom = [for c in ex.service.custom : merge(
                    { protocol = c.protocol },
                    try(length(c.port), 0) > 0 ? { port = [for p in c.port : tostring(p)] } : {},
                    try(c.portRange, null) != null ? { port_range = { from = tostring(c.portRange.from), to = tostring(c.portRange.to) } } : {}
                  )]
                } : {}
              )
            } : {}
          )
        )]
      } : {}
    )
  }
}

# Optional account-level policy toggle.
resource "cato_socket_bypass_policy" "policy" {
  count   = var.policy_enabled == null ? 0 : 1
  enabled = var.policy_enabled
}

resource "cato_socket_bypass_section" "sections" {
  for_each = local.sections_data
  at = {
    position = "LAST_IN_POLICY"
  }
  section = {
    name = each.value.section_name
  }
}

resource "cato_socket_bypass_rule" "rules" {
  depends_on = [cato_socket_bypass_section.sections]
  for_each   = local.rules_by_name

  at = contains(keys(local.sections_data), each.value.rule.section.name) ? {
    position = "LAST_IN_SECTION"
    ref      = cato_socket_bypass_section.sections[each.value.rule.section.name].id
    } : {
    position = "LAST_IN_POLICY"
  }

  rule = local.rule_bodies[each.key]
}

# Ordering + republish on changes.
resource "cato_bulk_sb_move_rule" "all_sb_rules" {
  depends_on = [cato_socket_bypass_section.sections, cato_socket_bypass_rule.rules]

  section_data = local.move_section_data
  rule_data    = local.move_rule_data
}
