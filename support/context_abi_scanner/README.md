# StackLab Context ABI Scanner

Scanner receipts for the fugu Context ABI path.

This package validates that context packets, authority grants, Mezzanine
admission receipts, render handoffs, model invocation receipts, optional
owner-local failure receipts, AppKit projections, and AITrace facts stay
ref-only and tenant-consistent.

It is a StackLab proof package. It does not own Context ABI semantics; those
remain in OuterBrain, Citadel, Mezzanine, Jido Integration, AppKit, and
AITrace.
