import Charts
import SwiftUI

// THESIS: The large panel can show the same observed quota history as Insights.
// OWN-WORLD: Existing native glass, system type, restrained provider color and fixed panel geometry.
// STORY: Choose a period and chart form; gaps stay gaps and percentages never become tokens.
// FIRST VIEWPORT: Two compact, aligned quota plots replace only the right-hand trend area.
// FORM: An extension of the current panel, with no new visual identity or motion layer.
struct PanelTrendView: View, Equatable {
    let presentation: PanelTrendPresentation
    let isLight: Bool
    let provider: AgentService

    private var secondaryText: Color { isLight ? .black.opacity(0.62) : .white.opacity(0.68) }
    private var gridColor: Color { isLight ? .black.opacity(0.08) : .white.opacity(0.1) }
    private var plotColor: Color {
        provider == .claude ? .orange : (isLight ? .indigo : Color(red: 0.32, green: 0.58, blue: 1))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("过去 \(presentation.source.hours ?? 24) 小时")
                    .font(.subheadline.weight(.semibold))
                Spacer(minLength: 8)
                Text("剩余额度（%）").font(.caption2).foregroundStyle(secondaryText)
            }
            if presentation.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("等待有效历史观测").font(.callout.weight(.medium))
                    Text(presentation.series.first?.message ?? presentation.message ?? "历史从启用采集后积累")
                        .font(.caption).foregroundStyle(secondaryText)
                    Text("空白不代表 0%，不会补造过去的数据。")
                        .font(.caption2).foregroundStyle(secondaryText)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            } else {
                ForEach(presentation.series) { series in
                    quotaPlot(series)
                }
                Text(presentation.style == .bars ? "横轴：本地时间 · 每小时末次有效观测" : "横轴：本地时间 · 缺口不连线")
                    .font(.system(size: 9)).foregroundStyle(secondaryText)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .help("与 Insights 相同的剩余百分比历史，不是 Token 或小时消耗。折线保留重置和缺失区段；柱状图取每小时最后一次有效观测，不填补没有观测的小时。")
    }

    private func quotaPlot(_ series: PanelTrendSeries) -> some View {
        let isolated = PanelTrendPresentation.isolatedSegmentIDs(in: series.points)
        return VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(series.title).font(.system(size: 10, weight: .medium))
                Spacer(minLength: 6)
                if !series.isFresh {
                    Text(series.points.isEmpty ? "暂无观测" : "旧记录 · 待更新")
                        .font(.system(size: 9)).foregroundStyle(secondaryText)
                }
            }
            if series.points.isEmpty {
                Text(series.message ?? "所选时段暂无观测")
                    .font(.caption2).foregroundStyle(secondaryText)
                    .frame(maxWidth: .infinity, minHeight: 54, alignment: .leading)
            } else {
                Chart {
                    if presentation.style == .line {
                        ForEach(series.points) { point in
                            LineMark(x: .value("收到时间", point.date),
                                     y: .value("剩余比例", point.remainingPercent),
                                     series: .value("连续观测区段", point.segmentID))
                                .interpolationMethod(.linear)
                                .lineStyle(StrokeStyle(lineWidth: 1.7))
                                .foregroundStyle(plotColor)
                            if isolated.contains(point.segmentID) {
                                PointMark(x: .value("收到时间", point.date),
                                          y: .value("剩余比例", point.remainingPercent))
                                    .symbolSize(9).foregroundStyle(plotColor)
                            }
                        }
                    } else {
                        ForEach(series.bars) { hour in
                            RectangleMark(xStart: .value("小时开始", insetStart(hour)),
                                          xEnd: .value("小时结束", insetEnd(hour)),
                                          yStart: .value("剩余比例基线", 0),
                                          yEnd: .value("小时末次剩余比例", hour.remainingPercent))
                                .foregroundStyle(plotColor.gradient).cornerRadius(1)
                            if hour.remainingPercent == 0 {
                                PointMark(x: .value("小时", hour.date), y: .value("剩余比例", 0))
                                    .symbolSize(6).foregroundStyle(plotColor)
                            }
                        }
                        if series.bars.isEmpty, let point = series.points.last {
                            // A valid point at an exact hour boundary has no positive-width hourly bar yet.
                            PointMark(x: .value("收到时间", point.date),
                                      y: .value("剩余比例", point.remainingPercent))
                                .symbolSize(9).foregroundStyle(plotColor)
                        }
                    }
                }
                .chartXScale(domain: presentation.domain.start...presentation.domain.end)
                .chartYScale(domain: 0...100)
                .chartLegend(.hidden)
                .chartXAxis {
                    AxisMarks(values: .stride(by: .hour, count: presentation.source.hours == 12 ? 3 : 6)) {
                        AxisGridLine().foregroundStyle(gridColor)
                        AxisValueLabel(format: UsageChartAxis.localTime).foregroundStyle(secondaryText)
                            .font(.system(size: 9))
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .trailing, values: [0, 50, 100]) {
                        AxisGridLine().foregroundStyle(gridColor)
                        AxisValueLabel(format: UsageChartAxis.remainingPercent)
                            .foregroundStyle(secondaryText).font(.system(size: 9))
                    }
                }
                .frame(height: 54)
                .accessibilityLabel("\(provider.title) \(series.title) 剩余百分比历史，\(presentation.style.title)，横轴为本地时间，纵轴为剩余额度百分比，重置和缺口处分段")
            }
        }
    }

    private func insetStart(_ hour: PanelTrendHour) -> Date {
        hour.startDate.addingTimeInterval(min(150, hour.endDate.timeIntervalSince(hour.startDate) / 6))
    }
    private func insetEnd(_ hour: PanelTrendHour) -> Date {
        hour.endDate.addingTimeInterval(-min(150, hour.endDate.timeIntervalSince(hour.startDate) / 6))
    }
}
