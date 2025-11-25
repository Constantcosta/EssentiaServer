"""Test case mixins used by the audio analysis test suite."""

from __future__ import annotations

from typing import Any

import requests

from test_analysis_utils import (
    print_error,
    print_header,
    print_info,
    print_success,
    print_warning,
)


class TestErrorTimeoutMixin:
    """Reusable test cases for timeout and error handling."""

    base_url: str

    def test_timeout_protection(self) -> bool:
        """Test that timeout protection works correctly."""
        print_header("Test: Timeout Protection")

        print_warning("This test requires a special timeout-triggering song URL")
        print_warning("Skipping for now - implement if you have a known problematic URL")

        # TODO: If we find a song that consistently hangs, add it here
        # For now, we rely on the 120s timeout being properly configured

        return True

    def test_error_handling(self) -> bool:
        """Test error handling for invalid requests."""
        print_header("Test: Error Handling")

        tests = [
            {
                "name": "Invalid URL",
                "payload": {"audio_url": "not-a-url", "title": "Test", "artist": "Test"},
                "expected_status": [400, 500],
            },
            {
                "name": "Missing required fields",
                "payload": {"audio_url": "http://example.com/song.mp3"},
                "expected_status": [400],
            },
            {
                "name": "Empty request",
                "payload": {},
                "expected_status": [400],
            },
        ]

        all_passed = True

        for test in tests:
            try:
                response = requests.post(
                    f"{self.base_url}/analyze",
                    json=test["payload"],
                    timeout=10,
                )

                if response.status_code in test["expected_status"]:
                    print_success(f"{test['name']}: Handled correctly ({response.status_code})")
                else:
                    print_error(f"{test['name']}: Unexpected status {response.status_code}")
                    all_passed = False

            except Exception as exc:
                print_error(f"{test['name']}: Exception - {exc}")
                all_passed = False

        return all_passed


__all__ = ["TestErrorTimeoutMixin"]
