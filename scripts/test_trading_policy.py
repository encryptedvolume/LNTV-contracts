"""Adversarial checks for release-policy validation; no chain access or signatures."""
import unittest
from trading_policy import PAYMENT_PROCESSORS, SIGNED_ZONE, check_trading_policy


class TradingPolicyTests(unittest.TestCase):
    def setUp(self):
        self.policy = dict(chain_id=1, edition="0x1111", market="0x2222", level=4,
                           list_id=5, recorded_list_id=5, list_owner="0x1111",
                           authorizers=[SIGNED_ZONE], operators=["0x2222", *PAYMENT_PROCESSORS], blacklist=[])

    def rejects(self, **changes):
        with self.assertRaises(AssertionError):
            check_trading_policy(**dict(self.policy, **changes))

    def test_exact_public_policies_pass(self):
        for chain in (1, 11155111):
            check_trading_policy(**dict(self.policy, chain_id=chain))

    def test_local_fixture_does_not_claim_live_processors(self):
        check_trading_policy(**dict(self.policy, chain_id=31337, operators=["0x2222"]))
        self.rejects(chain_id=31337)

    def test_unknown_chain_rejected(self):
        self.rejects(chain_id=8453)

    def test_unexpected_authorizer_rejected(self):
        self.rejects(authorizers=[SIGNED_ZONE, "0xbad"])
        self.rejects(authorizers=[])

    def test_unknown_operator_rejected(self):
        self.rejects(operators=[*self.policy["operators"], "0xbad"])
        self.rejects(operators=[*self.policy["operators"], "0x0000000000000068f116a894984e2db1123eb395"])

    def test_missing_processor_or_market_rejected(self):
        self.rejects(operators=["0x2222"])
        self.rejects(operators=list(PAYMENT_PROCESSORS))

    def test_old_wallet_list_owner_rejected(self):
        self.rejects(list_owner="0xold")

    def test_stale_list_identifier_rejected(self):
        self.rejects(list_id=6)
        self.rejects(list_id=0, recorded_list_id=0)

    def test_policy_downgrade_rejected(self):
        self.rejects(level=1)

    def test_nonempty_blacklist_rejected(self):
        self.rejects(blacklist=["0xbad"])


if __name__ == "__main__":
    unittest.main()
