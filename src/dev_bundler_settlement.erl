%%% @doc Completion hook for settling paid bundler uploads.
%%%
%%% P4 charges the uploader when the bundler POST succeeds. This hook runs after
%%% bundle completion, consumes the metered fee from the node's local ledger
%%% account, and optionally withdraws real AO to the beneficiary wallet.
-module(dev_bundler_settlement).
-export([info/1, bundled_message_complete/3, bundle_complete/3]).

-include_lib("hb/include/hb.hrl").

info(_) ->
    #{ exports => [<<"bundled-message-complete">>, <<"bundle-complete">>] }.

bundled_message_complete(Base, Req, Opts) ->
    settle(Base, Req, Opts).

bundle_complete(Base, Req, Opts) ->
    settle(Base, Req, Opts).

settle(Base, Req, Opts) ->
    Size = hb_util:int(hb_maps:get(<<"bundled-size">>, Req, 0, Opts)),
    case quote(Base, Size, Opts) of
        {ok, 0} ->
            {ok, Req};
        {ok, Amount} ->
            charge(Base, Req, Amount, Opts);
        Error ->
            Error
    end.

quote(Base, Size, Opts) ->
    PricingDevice =
        hb_maps:get(
            <<"pricing-device">>,
            Base,
            <<"arweave-byte-pricing@1.0">>,
            Opts
        ),
    hb_ao:resolve(
        Base#{ <<"device">> => PricingDevice },
        #{
            <<"path">> => <<"quote">>,
            <<"resource">> => <<"arweave-bytes">>,
            <<"amount">> => Size
        },
        Opts
    ).

charge(Base, Req, Amount, Opts) ->
    SignOpts = wallet_opts(Opts),
    Account = account(Base, Opts),
    Recipient = recipient(Base, Opts),
    LedgerRecipient = ledger_recipient(Base, Recipient, Opts),
    LedgerDevice =
        hb_maps:get(
            <<"ledger-device">>,
            Base,
            <<"ao-payment@1.0">>,
            Opts
        ),
    ChargeReq =
        hb_message:commit(
            #{
                <<"path">> => <<"charge">>,
                <<"quantity">> => Amount,
                <<"account">> => Account,
                <<"recipient">> => LedgerRecipient,
                <<"request">> => Req
            },
            SignOpts
        ),
    case hb_ao:resolve(Base#{ <<"device">> => LedgerDevice }, ChargeReq, SignOpts) of
        {ok, _} -> withdraw_if_enabled(Base, Req, Amount, Recipient, SignOpts);
        Error -> Error
    end.

withdraw_if_enabled(Base, Req, Amount, Recipient, Opts) ->
    case enabled(hb_maps:get(<<"withdraw">>, Base, false, Opts)) of
        false ->
            {ok, Req};
        true ->
            SignOpts = wallet_opts(Opts),
            AoPaymentDevice =
                hb_maps:get(
                    <<"withdraw-device">>,
                    Base,
                    <<"ao-payment@1.0">>,
                    Opts
                ),
            WithdrawReq0 = #{
                <<"path">> => <<"withdraw">>,
                <<"token">> => hb_maps:get(<<"withdraw-token">>, Base, undefined, Opts),
                <<"quantity">> => Amount,
                <<"recipient">> => Recipient,
                <<"withdraw-id">> => settlement_key(Req, Amount, Recipient, Opts),
                <<"request">> => Req
            },
            WithdrawReqWithSecret =
                case withdraw_secret(Base, SignOpts) of
                    undefined -> WithdrawReq0;
                    Secret -> WithdrawReq0#{<<"withdraw-secret">> => Secret}
                end,
            WithdrawReq1 =
                case hb_maps:get(<<"token">>, WithdrawReqWithSecret, undefined, Opts) of
                    undefined -> maps:remove(<<"token">>, WithdrawReqWithSecret);
                    _ -> WithdrawReqWithSecret
                end,
            WithdrawReq = hb_message:commit(WithdrawReq1, SignOpts),
            case hb_ao:resolve(Base#{ <<"device">> => AoPaymentDevice }, WithdrawReq, SignOpts) of
                {ok, _} -> {ok, Req};
                Error -> Error
            end
    end.

withdraw_secret(Base, Opts) ->
    hb_private:get(
        <<"withdraw-secret">>,
        Base,
        hb_private:get(<<"ao-payment-withdraw-secret">>, Opts, undefined, Opts),
        Opts
    ).

account(Base, Opts) ->
    normalize_account(
        hb_maps:get(
            <<"settlement-account">>,
            Base,
            hb_opts:get(p4_recipient, hb_opts:get(operator, undefined, Opts), Opts),
            Opts
        )
    ).

recipient(Base, Opts) ->
    normalize_account(
        hb_maps:get(
            <<"beneficiary">>,
            Base,
            hb_opts:get(bundler_beneficiary, hb_opts:get(operator, undefined, Opts), Opts),
            Opts
        )
    ).

ledger_recipient(Base, Recipient, Opts) ->
    case enabled(hb_maps:get(<<"withdraw">>, Base, false, Opts)) of
        true ->
            normalize_account(
                hb_maps:get(
                    <<"withdrawal-account">>,
                    Base,
                    hb_maps:get(<<"withdraw-token">>, Base, Recipient, Opts),
                    Opts
                )
            );
        false ->
            Recipient
    end.

enabled(true) -> true;
enabled(<<"true">>) -> true;
enabled(1) -> true;
enabled(<<"1">>) -> true;
enabled(_) -> false.

settlement_key(Req, Amount, Recipient, Opts) ->
    BaseKey =
        try hb_message:id(Req, all, Opts)
        catch
            _:_ ->
                hb_util:encode(crypto:hash(sha256, term_to_binary(Req)))
        end,
    <<BaseKey/binary, ":", (hb_util:bin(Amount))/binary, ":", Recipient/binary>>.

normalize_account(Account) when ?IS_ID(Account) ->
    hb_util:human_id(Account);
normalize_account(Account) ->
    Account.

wallet_opts(Opts) ->
    Wallet =
        case configured_wallet(Opts) of
            not_found ->
                hb:wallet(hb_opts:get(priv_key_location, <<"hyperbeam-key.json">>, Opts));
            FoundWallet ->
                FoundWallet
        end,
    Operator = hb_util:human_id(ar_wallet:to_address(Wallet)),
    Opts#{
        priv_wallet => Wallet,
        <<"priv-wallet">> => Wallet,
        operator => Operator,
        <<"operator">> => Operator
    }.

configured_wallet(Opts) when is_map(Opts) ->
    case maps:get(<<"priv-wallet">>, Opts, not_found) of
        not_found -> maps:get(priv_wallet, Opts, not_found);
        Wallet -> Wallet
    end;
configured_wallet(_Opts) ->
    not_found.

-ifdef(TEST).
-include_lib("eunit/include/eunit.hrl").

withdrawal_request_is_node_signed_test() ->
    Wallet = ar_wallet:new(),
    Operator = hb_util:human_id(ar_wallet:to_address(Wallet)),
    Opts = #{priv_wallet => Wallet, <<"priv-wallet">> => Wallet, <<"operator">> => Operator},
    Base = #{
        <<"withdraw">> => true,
        <<"withdraw-token">> => <<"0syT13r0s0tgPmIed95bJnuSqaD29HQNN8D3ElLSrsc">>,
        <<"settlement-account">> => Operator
    },
    Recipient = hb_util:encode(crypto:strong_rand_bytes(32)),
    SignOpts = wallet_opts(Opts),
    WithdrawReq0 = #{
        <<"path">> => <<"withdraw">>,
        <<"token">> => hb_maps:get(<<"withdraw-token">>, Base, undefined, Opts),
        <<"quantity">> => 7,
        <<"recipient">> => Recipient,
        <<"withdraw-id">> => settlement_key(#{<<"id">> => <<"item">>}, 7, Recipient, Opts)
    },
    WithdrawReq = hb_message:commit(WithdrawReq0, SignOpts),
    Signers = [hb_util:human_id(Signer) || Signer <- hb_message:signers(WithdrawReq, SignOpts)],
    ?assertEqual(true, hb_message:verify(WithdrawReq, signers, SignOpts)),
    ?assert(lists:member(Operator, Signers)),
    ?assertEqual(undefined, maps:get(<<"withdraw-secret">>, WithdrawReq, undefined)).

-endif.
