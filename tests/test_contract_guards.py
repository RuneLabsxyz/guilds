from pathlib import Path
import shutil
import subprocess
import unittest


REPO_ROOT = Path(__file__).resolve().parents[1]
GUILD_CONTRACT = REPO_ROOT / "src" / "guild" / "guild_contract.cairo"


def _guild_contract_source() -> str:
    return GUILD_CONTRACT.read_text(encoding="utf-8")


class ContractGuardsTests(unittest.TestCase):
    def test_plugin_registration_guards_present(self) -> None:
        source = _guild_contract_source()

        self.assertIn("PLUGIN_TARGET_INVALID", source)
        self.assertIn("PLUGIN_ACTION_COUNT_ZERO", source)
        self.assertIn("PLUGIN_OFFSET_COLLISION", source)
        self.assertIn("plugin_action_mask: u32", source)
        self.assertIn("assert!(target_contract != Zero::zero()", source)
        self.assertIn("assert!(action_count > 0", source)
        self.assertIn("current_plugin_mask & new_plugin_mask == 0", source)

    def test_role_and_lifecycle_guards_present(self) -> None:
        source = _guild_contract_source()

        self.assertIn("GUILD_NAME_INVALID", source)
        self.assertIn("GUILD_TICKER_INVALID", source)
        self.assertIn("INVALID_ROLE_NAME", source)
        self.assertIn("TOKEN_ADDRESS_INVALID", source)
        self.assertIn("GOVERNOR_ADDRESS_INVALID", source)
        self.assertIn("FOUNDER_ADDRESS_INVALID", source)
        self.assertIn("ROLE_HAS_MEMBERS", source)
        self.assertIn("assert!(guild_name != 0", source)
        self.assertIn("assert!(guild_ticker != 0", source)
        self.assertIn("assert!(token_address != Zero::zero()", source)
        self.assertIn("assert!(governor_address != Zero::zero()", source)
        self.assertIn("assert!(founder != Zero::zero()", source)
        self.assertIn("assert!(role.name != 0", source)
        self.assertIn("assert!(founder_role.name != 0", source)
        self.assertIn("assert!(!founder_role.can_be_kicked", source)
        self.assertIn("self.role_member_count.read(role_id) == 0", source)
        self.assertIn("self.assert_not_member(caller);", source)
        self.assertIn("old_role_id == 0 && new_role_id != 0", source)
        self.assertIn("self.founder_count.read() > 1", source)

    def test_core_action_input_guards_present(self) -> None:
        source = _guild_contract_source()

        self.assertIn("CORE_TARGET_INVALID", source)
        self.assertIn("CORE_TOKEN_INVALID", source)
        self.assertIn("if action_type == ActionType::TRANSFER", source)
        self.assertIn("else if action_type == ActionType::APPROVE", source)
        self.assertIn("else if action_type == ActionType::EXECUTE", source)
        self.assertIn("assert!(target != Zero::zero()", source)
        self.assertIn("assert!(token != Zero::zero()", source)

    def test_share_offer_guards_present(self) -> None:
        source = _guild_contract_source()

        self.assertIn("OFFER_DEPOSIT_TOKEN_INVALID", source)
        self.assertIn("OFFER_MAX_TOTAL_INVALID", source)
        self.assertIn("OFFER_PRICE_INVALID", source)
        self.assertIn("OFFER_EXPIRY_INVALID", source)
        self.assertIn("OFFER_COST_ZERO", source)
        self.assertIn("assert!(offer.deposit_token != Zero::zero()", source)
        self.assertIn("assert!(offer.max_total > 0", source)
        self.assertIn("assert!(offer.price_per_share > 0", source)
        self.assertIn("offer.expires_at > get_block_timestamp()", source)
        self.assertIn("assert!(cost > 0", source)

    def test_redemption_window_guards_present(self) -> None:
        source = _guild_contract_source()

        self.assertIn("REDEMPTION_MAX_INVALID", source)
        self.assertIn("REDEMPTION_EPOCH_USAGE_INVALID", source)
        self.assertIn("REDEMPTION_PAYOUT_ZERO", source)
        self.assertIn("window.max_per_epoch > 0", source)
        self.assertIn("window.redeemed_this_epoch == 0", source)
        self.assertIn("assert!(payout > 0", source)

    def test_revenue_token_guards_present(self) -> None:
        source = _guild_contract_source()

        self.assertIn("REVENUE_TOKEN_INVALID", source)
        self.assertIn("REVENUE_BALANCE_BELOW_CHECKPOINT", source)
        self.assertIn("assert!(token != Zero::zero()", source)
        self.assertIn("current_balance >= checkpoint", source)

    def test_reentrancy_sensitive_paths_use_effects_before_interactions(self) -> None:
        source = _guild_contract_source()

        buy_start = source.index("fn buy_shares(")
        buy_end = source.index("fn set_redemption_window(", buy_start)
        buy_block = source[buy_start:buy_end]
        self.assertLess(
            buy_block.index("offer.minted_so_far = next_minted;"),
            buy_block.index(".transfer_from(caller, get_contract_address(), cost);"),
        )

        player_start = source.index("fn claim_player_revenue(")
        player_end = source.index("fn claim_shareholder_revenue(", player_start)
        player_block = source[player_start:player_end]
        self.assertLess(
            player_block.index("self.member_last_claimed_epoch.write(caller, epoch + 1);"),
            player_block.index(".transfer(caller, share);"),
        )

        shareholder_start = source.index("fn claim_shareholder_revenue(")
        shareholder_end = source.index("fn create_share_offer(", shareholder_start)
        shareholder_block = source[shareholder_start:shareholder_end]
        self.assertLess(
            shareholder_block.index(
                "self.shareholder_last_claimed_epoch.write(caller, epoch + 1);"
            ),
            shareholder_block.index(".transfer(caller, share);"),
        )

        redeem_start = source.index("fn redeem_shares(")
        redeem_end = source.index("fn dissolve(", redeem_start)
        redeem_block = source[redeem_start:redeem_end]
        self.assertLess(
            redeem_block.index("self.redemption_window.write(window);"),
            redeem_block.index(".burn(caller, amount);"),
        )
        self.assertLess(
            redeem_block.index(
                "self.member_last_redemption_epoch.write(caller, current_epoch);"
            ),
            redeem_block.index(".transfer(caller, payout);"),
        )

    def test_optional_cairo_contract_tests_pass(self) -> None:
        snforge = shutil.which("snforge")
        if snforge is None:
            self.skipTest("snforge not installed in this environment")

        cmd = [snforge, "test"]
        result = subprocess.run(
            cmd,
            cwd=REPO_ROOT,
            capture_output=True,
            text=True,
            check=False,
        )
        self.assertEqual(
            result.returncode,
            0,
            msg=(
                f"{' '.join(cmd)} failed with exit code {result.returncode}\n"
                f"stdout:\n{result.stdout}\n"
                f"stderr:\n{result.stderr}"
            ),
        )

if __name__ == "__main__":
    unittest.main()
