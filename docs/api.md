# API

## `bundled_message_complete/3`

Primary bundle-completion hook. Reads `bundled-size`, quotes the byte cost,
charges the configured ledger device, and optionally withdraws to the configured
beneficiary.

## `bundle_complete/3`

Compatibility alias for `bundled_message_complete/3`.

Configuration keys:

- `pricing-device`: defaults to `arweave-byte-pricing@1.0`.
- `ledger-device`: defaults to `ao-payment@1.0`.
- `settlement-account`: ledger account to debit; defaults to `p4_recipient` or `operator`.
- `beneficiary`: AO withdrawal recipient; defaults to `bundler_beneficiary` or `operator`.
- `withdraw`: boolean, disabled by default.
- `withdraw-device`: defaults to `ao-payment@1.0`.
- `withdraw-token`, `withdraw-recipient`, `withdrawal-account`, `withdraw-secret`.
