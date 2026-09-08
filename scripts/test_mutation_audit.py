#!/usr/bin/env python3
"""Reject misleading mutation evidence: compile/setup failures, getter-only kills and missing scenarios."""
import json
import subprocess
import unittest

from mutation_audit import CONFIGURATION_TESTS, REQUIRED_BEHAVIORS, collect_tests, evaluate_mutation, validate_baseline

A = "test/Fixture.t.sol:FixtureTest::testFirstBehavior()"
B = "test/Fixture.t.sol:FixtureTest::testSecondBehavior()"
CONFIG = sorted(CONFIGURATION_TESTS)[0]


def run_result(statuses, returncode=1, stderr=""):
    suites = {}
    for identifier, status in statuses.items():
        suite, test = identifier.split("::")
        suites.setdefault(suite, {"test_results": {}})["test_results"][test] = {
            "status": status, "reason": "fixture assertion" if status == "Failure" else None,
        }
    return subprocess.CompletedProcess([], returncode, json.dumps(suites), stderr)


class MutationAuditTests(unittest.TestCase):
    def test_two_behavioral_failures_pass_and_keep_attribution(self):
        run = run_result({A: "Failure", B: "Failure", CONFIG: "Success"})
        result = evaluate_mutation("fixture", run, {A, B, CONFIG})
        self.assertTrue(result["killed"])
        self.assertTrue(result["strengthPassed"])
        self.assertEqual(result["behavioralFailures"], [A, B])
        self.assertEqual(result["failureReasons"][A], "fixture assertion")

    def test_one_behavior_and_configuration_failure_do_not_pass(self):
        run = run_result({A: "Failure", CONFIG: "Failure"})
        result = evaluate_mutation("fixture", run, {A, CONFIG})
        self.assertTrue(result["killed"])
        self.assertFalse(result["strengthPassed"])
        self.assertEqual(result["behavioralFailures"], [A])

    def test_getter_only_failures_do_not_pass(self):
        run = run_result({name: "Failure" for name in CONFIGURATION_TESTS})
        result = evaluate_mutation("fixture", run, CONFIGURATION_TESTS)
        self.assertFalse(result["strengthPassed"])
        self.assertEqual(result["behavioralFailures"], [])

    def test_successful_exit_cannot_count_as_a_kill(self):
        result = evaluate_mutation("fixture", run_result({A: "Failure", B: "Failure"}, 0), {A, B})
        self.assertFalse(result["killed"])
        self.assertFalse(result["strengthPassed"])

    def test_crashed_process_cannot_count_as_a_kill(self):
        result = evaluate_mutation("fixture", run_result({A: "Failure", B: "Failure"}, -9), {A, B})
        self.assertFalse(result["killed"])
        self.assertFalse(result["strengthPassed"])

    def test_compile_failure_cannot_count_as_a_kill(self):
        run = run_result({A: "Failure", B: "Failure"}, stderr="Compiler run failed")
        result = evaluate_mutation("fixture", run, {A, B})
        self.assertFalse(result["killed"])
        self.assertEqual(result["error"], "Compilation failed")

    def test_non_json_and_empty_reports_do_not_pass(self):
        for stdout in ["[FAIL: Compiler run failed]", "{}", "[]", "null"]:
            with self.subTest(stdout=stdout):
                run = subprocess.CompletedProcess([], 1, stdout, "")
                self.assertFalse(evaluate_mutation("fixture", run, {A, B})["strengthPassed"])

    def test_setup_failure_is_not_a_behavioral_test(self):
        setup = "test/Fixture.t.sol:FixtureTest::setUp()"
        result = evaluate_mutation("fixture", run_result({setup: "Failure"}), {A, B})
        self.assertFalse(result["killed"])
        self.assertIn("Non-test failure", result["error"])

    def test_skipped_test_is_rejected(self):
        with self.assertRaises(ValueError):
            collect_tests(run_result({A: "Skipped"}).stdout)

    def test_changed_inventory_is_rejected(self):
        result = evaluate_mutation("fixture", run_result({A: "Failure", B: "Failure"}), {A, B, CONFIG})
        self.assertFalse(result["killed"])
        self.assertIn("inventory differs", result["error"])

    def test_duration_requires_the_reviewed_behavioral_scenarios(self):
        result = evaluate_mutation("wrong initial duration", run_result({A: "Failure", B: "Failure"}), {A, B})
        self.assertTrue(result["killed"])
        self.assertFalse(result["strengthPassed"])
        self.assertEqual(len(result["missingRequiredBehaviors"]), 2)

    def test_recovery_requires_qualified_behavioral_scenarios(self):
        result = evaluate_mutation("recovery authorization removed", run_result({A: "Failure", B: "Failure"}), {A, B})
        self.assertFalse(result["strengthPassed"])
        self.assertEqual(len(result["missingRequiredBehaviors"]), 2)

    def test_qualified_recovery_failures_satisfy_the_gate(self):
        names = REQUIRED_BEHAVIORS["recovery authorization removed"]
        result = evaluate_mutation("recovery authorization removed", run_result({name: "Failure" for name in names}), set(names))
        self.assertTrue(result["strengthPassed"])
        self.assertEqual(result["missingRequiredBehaviors"], [])

    def test_clean_baseline_passes_and_existing_failures_stop_the_campaign(self):
        self.assertEqual(set(validate_baseline(run_result({A: "Success", B: "Success"}, 0))), {A, B})
        for statuses, exit_code in [({A: "Failure", B: "Success"}, 1), ({A: "Success"}, 1), ({A: "Failure"}, 0)]:
            with self.subTest(statuses=statuses, exit_code=exit_code):
                with self.assertRaises(RuntimeError):
                    validate_baseline(run_result(statuses, exit_code))


if __name__ == "__main__":
    unittest.main()
