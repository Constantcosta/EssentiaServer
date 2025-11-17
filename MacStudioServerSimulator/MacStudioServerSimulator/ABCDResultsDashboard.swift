//
//  ABCDResultsDashboard.swift
//  MacStudioServerSimulator
//
//  Results dashboard for ABCD tests
//

import SwiftUI
import Charts

struct ABCDResultsDashboard: View {
    @ObservedObject var testRunner: ABCDTestRunner
    
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                Text("📊 Test Results")
                    .font(.title2)
                    .fontWeight(.bold)
                    .padding(.top)
                
                if testRunner.results.isEmpty {
                    EmptyResultsView()
                } else {
                    // Overall Summary
                    OverallSummaryCard(results: testRunner.results)
                    
                    // Performance Chart
                    PerformanceChart(results: testRunner.results)
                    
                    // Individual Results
                    VStack(spacing: 12) {
                        Text("Individual Test Results")
                            .font(.headline)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        
                        ForEach(ABCDTestType.allCases, id: \.self) { test in
                            if let result = testRunner.results[test] {
                                TestResultCard(result: result)
                            } else {
                                PlaceholderCard(test: test)
                            }
                        }
                    }
                    
                    // Spotify Reference Comparison
                    TestComparisonView(results: testRunner.results)
                }
            }
            .padding()
        }
    }
}

// MARK: - Empty State

struct EmptyResultsView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "chart.bar.xaxis")
                .font(.system(size: 60))
                .foregroundColor(.secondary)
            
            Text("No Test Results Yet")
                .font(.title3)
                .fontWeight(.semibold)
            
            Text("Run tests from the left panel to see results here")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(40)
    }
}

// MARK: - Overall Summary

struct OverallSummaryCard: View {
    let results: [ABCDTestType: ABCDTestResult]
    
    private var passedCount: Int {
        results.values.filter { $0.passed }.count
    }
    
    private var totalTests: Int {
        ABCDTestType.allCases.count
    }
    
    private var totalDuration: Double {
        results.values.reduce(0) { $0 + $1.duration }
    }
    
    private var totalSuccess: Int {
        results.values.reduce(0) { $0 + $1.successCount }
    }
    
    private var totalCount: Int {
        results.values.reduce(0) { $0 + $1.totalCount }
    }
    
    var body: some View {
        VStack(spacing: 16) {
            Text("Overall Summary")
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .leading)
            
            HStack(spacing: 20) {
                SummaryMetric(
                    icon: "checkmark.circle.fill",
                    iconColor: passedCount == totalTests ? .green : .orange,
                    title: "Pass Rate",
                    value: "\(passedCount)/\(totalTests)",
                    subtitle: "\(Int(Double(passedCount) / Double(totalTests) * 100))%"
                )
                
                Divider()
                
                SummaryMetric(
                    icon: "clock.fill",
                    iconColor: .blue,
                    title: "Total Time",
                    value: String(format: "%.1fs", totalDuration),
                    subtitle: totalTests > 0 ? "Avg: \(String(format: "%.1fs", totalDuration / Double(results.count)))" : ""
                )
                
                Divider()
                
                SummaryMetric(
                    icon: "chart.bar.fill",
                    iconColor: totalSuccess == totalCount ? .green : .orange,
                    title: "Files",
                    value: "\(totalSuccess)/\(totalCount)",
                    subtitle: totalCount > 0 ? "\(Int(Double(totalSuccess) / Double(totalCount) * 100))%" : "0%"
                )
            }
        }
        .padding()
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(10)
    }
}

struct SummaryMetric: View {
    let icon: String
    let iconColor: Color
    let title: String
    let value: String
    let subtitle: String
    
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(iconColor)
            
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
            
            Text(value)
                .font(.title3)
                .fontWeight(.bold)
            
            if !subtitle.isEmpty {
                Text(subtitle)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Performance Chart

struct PerformanceChart: View {
    let results: [ABCDTestType: ABCDTestResult]
    
    private var chartData: [(test: String, duration: Double, expected: Double)] {
        ABCDTestType.allCases.compactMap { test in
            guard let result = results[test] else { return nil }
            return (test.name, result.duration, test.expectedDuration)
        }
    }
    
    var body: some View {
        VStack(spacing: 12) {
            Text("Performance Comparison")
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .leading)
            
            if #available(macOS 13.0, *) {
                Chart {
                    ForEach(chartData, id: \.test) { item in
                        BarMark(
                            x: .value("Test", item.test),
                            y: .value("Duration", item.duration)
                        )
                        .foregroundStyle(item.duration <= item.expected ? Color.green : Color.orange)
                        .annotation(position: .top) {
                            Text("\(String(format: "%.1f", item.duration))s")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .frame(height: 200)
                .padding()
            } else {
                // Fallback for older macOS
                VStack(spacing: 8) {
                    ForEach(chartData, id: \.test) { item in
                        HStack {
                            Text(item.test)
                                .font(.caption)
                                .frame(width: 60, alignment: .leading)
                            
                            GeometryReader { geo in
                                ZStack(alignment: .leading) {
                                    Rectangle()
                                        .fill(Color.gray.opacity(0.2))
                                    
                                    Rectangle()
                                        .fill(item.duration <= item.expected ? Color.green : Color.orange)
                                        .frame(width: min(geo.size.width * CGFloat(item.duration / item.expected), geo.size.width))
                                }
                            }
                            .frame(height: 20)
                            
                            Text("\(String(format: "%.1f", item.duration))s")
                                .font(.caption)
                                .frame(width: 50, alignment: .trailing)
                        }
                    }
                }
                .padding()
            }
            
            HStack {
                Image(systemName: "info.circle")
                    .foregroundColor(.secondary)
                    .font(.caption)
                Text("Green = within expected time, Orange = slower")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(10)
    }
}

// MARK: - Test Result Card

struct TestResultCard: View {
    let result: ABCDTestResult
    
    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Image(systemName: result.passed ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .font(.title2)
                    .foregroundColor(result.passed ? .green : .red)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(result.testType.name)
                        .font(.headline)
                    
                    Text("\(result.successCount) of \(result.totalCount) files")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 4) {
                    Text("\(String(format: "%.2f", result.duration))s")
                        .font(.title3)
                        .fontWeight(.semibold)
                    
                    Text(result.timestamp, style: .time)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            
            // Progress Bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Rectangle()
                        .fill(Color.gray.opacity(0.2))
                        .cornerRadius(4)
                    
                    Rectangle()
                        .fill(result.passed ? Color.green : Color.orange)
                        .frame(width: geo.size.width * CGFloat(result.successCount) / CGFloat(result.totalCount))
                        .cornerRadius(4)
                }
            }
            .frame(height: 8)
            
            // Details
            HStack(spacing: 12) {
                DetailBadge(
                    icon: "gauge.medium",
                    text: "\(Int(Double(result.successCount) / Double(result.totalCount) * 100))%",
                    color: result.passed ? .green : .orange
                )
                
                DetailBadge(
                    icon: "timer",
                    text: String(format: "%.1fs avg", result.duration / Double(result.totalCount)),
                    color: .purple
                )
                
                if result.duration <= result.testType.expectedDuration {
                    DetailBadge(
                        icon: "checkmark.circle",
                        text: "On time",
                        color: .green
                    )
                } else {
                    DetailBadge(
                        icon: "clock",
                        text: "+\(String(format: "%.1f", result.duration - result.testType.expectedDuration))s",
                        color: .orange
                    )
                }
                
                Spacer()
            }
        }
        .padding()
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(result.passed ? Color.green.opacity(0.5) : Color.red.opacity(0.5), lineWidth: 1)
        )
    }
}

struct PlaceholderCard: View {
    let test: ABCDTestType
    
    var body: some View {
        HStack {
            Image(systemName: "circle.dashed")
                .foregroundColor(.gray)
            
            Text(test.name)
                .foregroundColor(.secondary)
            
            Spacer()
            
            Text("Not run yet")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.gray.opacity(0.3), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
        )
    }
}

struct DetailBadge: View {
    let icon: String
    let text: String
    let color: Color
    
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.caption2)
            Text(text)
                .font(.caption2)
        }
        .foregroundColor(color)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(color.opacity(0.15))
        .cornerRadius(4)
    }
}

#Preview {
    ABCDResultsDashboard(testRunner: ABCDTestRunner())
}
