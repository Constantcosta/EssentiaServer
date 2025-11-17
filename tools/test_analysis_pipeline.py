#!/usr/bin/env python3
"""CLI wrapper for audio analysis tests (delegates to test_analysis_suite)."""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

# Add backend to path
sys.path.insert(0, str(Path(__file__).parent.parent / "backend"))

from test_analysis_suite import (
    AnalysisTestSuite,
    Colors,
    print_error,
    print_header,
    print_info,
    print_success,
    save_results_to_csv,
)

def main():
    parser = argparse.ArgumentParser(description="Test audio analysis pipeline")
    parser.add_argument('--preview-batch', action='store_true', help='Test a) 6 preview files')
    parser.add_argument('--full-batch', action='store_true', help='Test b) 6 full-length songs')
    parser.add_argument('--preview-calibration', action='store_true', help='Test c) 12 preview files (2 batches)')
    parser.add_argument('--full-calibration', action='store_true', help='Test d) 12 full-length songs (2 batches)')
    parser.add_argument('--all', action='store_true', help='Run all four test scenarios')
    parser.add_argument('--url', default='http://127.0.0.1:5050', help='Server URL')
    parser.add_argument('--csv', type=str, help='Export results to CSV file (optional: specify filename)')
    parser.add_argument('--csv-auto', action='store_true', help='Automatically export results to timestamped CSV file')
    parser.add_argument('--allow-cache', action='store_true', help='Allow cached analysis responses (default forces re-analysis)')
    parser.add_argument('--cache-namespace', default='gui-tests', help='Cache namespace for test runs')
    
    args = parser.parse_args()
    
    # If no specific test selected, show help
    if not any([args.preview_batch, args.full_batch, args.preview_calibration, args.full_calibration, args.all]):
        print_header("Audio Analysis Test Suite")
        print("Available tests:")
        print("  a) --preview-batch         : 6 preview files (basic multithread test)")
        print("  b) --full-batch           : 6 full-length songs (full songs work)")
        print("  c) --preview-calibration  : 12 preview files in 2 batches (batch sequencing)")
        print("  d) --full-calibration     : 12 full songs in 2 batches (full-length batch sequencing)")
        print("  --all                      : Run all tests a, b, c, d")
        print("\nRun with --help for more options")
        sys.exit(0)
    
    suite = AnalysisTestSuite(
        base_url=args.url,
        force_reanalyze=not args.allow_cache,
        cache_namespace=args.cache_namespace,
    )
    
    # Check server first
    if not suite.check_server_health():
        sys.exit(1)
    
    suite.get_diagnostics()
    
    success = True
    results = {}
    
    if args.all or args.preview_batch:
        print_info("\n" + "="*80)
        print_info("TEST A: 6 Preview Files (Basic Multithread Test)")
        print_info("="*80)
        results['a) 6 previews'] = suite.test_batch_analysis(batch_size=6, use_preview=True, test_name="Test A: 6 previews")
        success = success and results['a) 6 previews']
    
    if args.all or args.full_batch:
        print_info("\n" + "="*80)
        print_info("TEST B: 6 Full-Length Songs (Full Songs Work)")
        print_info("="*80)
        results['b) 6 full songs'] = suite.test_batch_analysis(batch_size=6, use_preview=False, test_name="Test B: 6 full songs")
        success = success and results['b) 6 full songs']
    
    if args.all or args.preview_calibration:
        print_info("\n" + "="*80)
        print_info("TEST C: 12 Preview Files (Batch Sequencing)")
        print_info("="*80)
        results['c) 12 previews'] = suite.test_full_calibration(use_preview=True)
        success = success and results['c) 12 previews']
    
    if args.all or args.full_calibration:
        print_info("\n" + "="*80)
        print_info("TEST D: 12 Full-Length Songs (Full-Length Batch Sequencing)")
        print_info("="*80)
        results['d) 12 full songs'] = suite.test_full_calibration(use_preview=False)
        success = success and results['d) 12 full songs']
    
    # Summary
    if results:
        print_header("Test Summary")
        passed = sum(results.values())
        total = len(results)
        
        for test_name, result in results.items():
            if result:
                print_success(f"{test_name}")
            else:
                print_error(f"{test_name}")
        
        print(f"\n{Colors.BOLD}Results: {passed}/{total} tests passed{Colors.RESET}")
        
        if passed == total:
            print_success("All tests passed! 🎉")
        else:
            print_error(f"{total - passed} test(s) failed")
    
    # Export to CSV if requested
    if args.csv or args.csv_auto:
        print("\n")
        filename = args.csv if args.csv else None
        save_results_to_csv(suite.all_results, filename)
    
    sys.exit(0 if success else 1)


if __name__ == '__main__':
    main()


if __name__ == "__main__":
    main()
