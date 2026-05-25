# StackLab Router Fabric Scanner

`stack_lab_router_fabric_scanner` validates provider-free router fabric proof
receipts.

It checks that route requests and route decisions stay ref-only, that TRINITY
adapter decisions preserve packet, authority, policy, model, and trace refs,
and that no raw prompts, provider payloads, credentials, or private model
outputs cross the route boundary.

The scanner is proof infrastructure owned by StackLab. It does not own route
semantics, workflow truth, context compilation, model invocation, or AppKit
projection behavior.
