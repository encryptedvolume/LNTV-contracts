"""Fail closed unless the complete registry policy matches the reviewed release policy.

Public-chain processors were observed in the 2026-09-08 Ethereum/Sepolia fork
review. An upstream curated-list change requires review and an explicit update;
it is never accepted merely because an address is not a known Seaport conduit.
"""

SIGNED_ZONE = "0x000056f7000000ece9003ca63978907a00ffd100"
PAYMENT_PROCESSORS = {
    "0x9a1d00bed7cd04bcda516d721a596eb22aac6834",
    "0x9a1d001670c8b17f8b7900e8d7a41e785b3f0515",
}


def check_trading_policy(*, chain_id, edition, market, level, list_id,
                         recorded_list_id, list_owner, authorizers, operators, blacklist):
    assert chain_id in (1, 11155111, 31337), "Unreviewed chain policy"
    assert level == 4, "Expected strict security level 4"
    assert list_id == recorded_list_id and list_id > 0, "Unexpected active trading list"
    assert list_owner.lower() == edition.lower(), "Trading list must be owned by the edition"
    assert {a.lower() for a in authorizers} == {SIGNED_ZONE}, "Unexpected authorizer set"
    expected = {market.lower()}
    if chain_id != 31337:
        expected |= PAYMENT_PROCESSORS
    assert {a.lower() for a in operators} == expected, "Unexpected operator set"
    assert not blacklist, "Unexpected operator-requiring-authorization list"
