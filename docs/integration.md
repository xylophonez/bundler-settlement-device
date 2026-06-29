# Integration

Install this as a `bundled-message-complete` hook after p4 has charged the user
for a successful bundler upload. The hook settles against the local ledger and
can withdraw through `ao-payment@1.0`.

Typical hook:

```erlang
#{
    <<"device">> => <<"bundler-settlement@1.0">>,
    <<"ledger-device">> => <<"ao-payment@1.0">>,
    <<"pricing-device">> => <<"arweave-byte-pricing@1.0">>,
    <<"withdraw">> => true,
    <<"hook">> => #{<<"result">> => <<"ignore">>}
}
```
