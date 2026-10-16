# Hub-and-spoke with centralized inspection (AWS)

Two spoke VPCs and one hub (inspection) VPC connected by a Transit Gateway. All
spoke traffic, both **east-west** (spoke ↔ spoke) and **egress** (spoke → internet),
passes through **AWS Network Firewall** in the hub before going anywhere else.

```
                                   Internet
                                       │
                                  ┌────┴────┐
                                  │   IGW   │
  Hub VPC 10.0.0.0/16             └────┬────┘
  ┌────────────────────────────────────┼─────────────────────────────┐
  │  public subnet   (per AZ)     NAT Gateway                        │
  │                                    │                             │
  │  firewall subnet (per AZ)     Network Firewall endpoint          │
  │                                    │                             │
  │  tgw subnet      (per AZ)     TGW attachment (appliance mode)    │
  └────────────────────────────────────┼─────────────────────────────┘
                                       │
                              ┌────────┴────────┐
                              │ Transit Gateway │
                              └───┬─────────┬───┘
                                  │         │
             Spoke A 10.1.0.0/16  │         │  Spoke B 10.2.0.0/16
             ┌────────────────────┴──┐   ┌──┴────────────────────┐
             │ workload subnets      │   │ workload subnets      │
             │ 0.0.0.0/0 -> TGW      │   │ 0.0.0.0/0 -> TGW      │
             └───────────────────────┘   └───────────────────────┘
```

## Routing

| Where | Destination | Target |
|---|---|---|
| Spoke workload subnets | `0.0.0.0/0` | TGW |
| TGW route table **spokes** (spoke attachments) | `0.0.0.0/0` | hub attachment |
| TGW route table **inspection** (hub attachment) | spoke CIDRs (propagated) | spoke attachments |
| Hub tgw subnet (per AZ) | `0.0.0.0/0` | firewall endpoint (same AZ) |
| Hub firewall subnet (per AZ) | `10.0.0.0/8` | TGW |
| | `0.0.0.0/0` | NAT gateway (same AZ) |
| Hub public subnet (per AZ) | spoke CIDRs | firewall endpoint (same AZ) |
| | `0.0.0.0/0` | IGW |

Because the spokes route table only knows `0.0.0.0/0 → hub`, spokes can't reach
each other directly; they have to go through the firewall. Appliance mode on the hub
attachment keeps both directions of a flow in the same AZ, so the stateful firewall
sees the whole connection.

**East-west:** Spoke A → TGW → hub tgw subnet → firewall → TGW → Spoke B
**Egress:** Spoke → TGW → hub tgw subnet → firewall → NAT → IGW (return traffic comes back through the firewall)

## Firewall policy

Rules are evaluated in strict order, and the default action is **drop established + alert**:

1. ICMP between spokes: allowed
2. TCP between spokes on `east_west_tcp_ports` (default 22, 80, 443): allowed
3. HTTPS (TLS SNI) / HTTP (Host header) to `allowed_egress_domains` and their subdomains: allowed
4. Everything else: dropped and logged to `/<name>/network-firewall/alert`

Flow logs go to `/<name>/network-firewall/flow`.

## Deploy

```bash
cp terraform.tfvars.example terraform.tfvars   # optional, defaults work as-is
terraform init
terraform plan
terraform apply
```

The deploy takes about 10–15 minutes, most of it spent creating the Network Firewall.

## Test

With `create_test_instances = true` (the default), you get one Amazon Linux instance per
spoke, managed through SSM. They have no public IP and no inbound SSH.

```bash
terraform output test_instances
aws ssm start-session --target <spoke-a instance id>
```

From the Spoke A instance:

```bash
ping -c3 <spoke-b private ip>          # allowed (east-west ICMP)
curl -sI https://aws.amazon.com        # allowed (domain on the allow-list)
curl -sI --max-time 5 https://example.com   # dropped by the firewall
```

Look in the alert log group to see the dropped `example.com` flow.

## Cost

Network Firewall endpoints, NAT gateways and TGW attachments are all billed by the
hour. With 2 AZs this comes to roughly $1/hour before data processing. Run
`terraform destroy` when you're done.

## Layout

```
versions.tf          provider configuration
variables.tf         inputs
hub.tf               hub VPC, subnets, NAT, per-AZ route tables
tgw.tf               Transit Gateway, attachments, route tables
firewall.tf          Network Firewall, rule group, policy, logging
spokes.tf            spoke VPC module calls
modules/spoke_vpc/   reusable spoke VPC + TGW attachment
test_instances.tf    optional SSM test instances
outputs.tf
```
