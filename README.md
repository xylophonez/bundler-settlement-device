# Bundler Settlement Device

Standalone HyperBEAM Forge package for `bundler-settlement@1.0`.

Settles paid bundler uploads after bundle completion.

It re-quotes the completed bundle size, charges the local ledger via the configured p4 ledger device, and can trigger guarded AO withdrawals to the bundler beneficiary.

## Compatibility

- HyperBEAM pin: `4177b91993b2f590f4906bc9ca548724f8408875`
- Device name: `bundler-settlement@1.0`

## Build

```sh
rebar3 compile
rebar3 device package
rebar3 device verify
```

## Test

```sh
scripts/pre-push-test.sh
```

Install the local pre-push hook with:

```sh
scripts/install-git-hooks.sh
```

## Docs

- `docs/api.md`
- `docs/integration.md`
- `docs/generated.md`

Regenerate EDoc HTML with:

```sh
scripts/generate-docs.sh
```

## Publish

After tests pass, publish the Forge package artifacts generated under
`_build/device-packages/` with your normal ANS-104 item pipeline. Then pin the
published spec ID in your node's `name-resolvers` and trust the publisher
address in `trusted-device-signers`.
