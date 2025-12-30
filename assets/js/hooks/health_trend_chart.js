import Chart from 'chart.js/auto';

export const HealthTrendChart = {
  mounted() {
    const raw = this.el.dataset.chartData;
    if (!raw) {
      console.warn('HealthTrendChart: missing data-chart-data');
      return;
    }

    let chartData;
    try {
      chartData = JSON.parse(raw);
    } catch (e) {
      console.error('HealthTrendChart: invalid chartData JSON', e);
      return;
    }

    this.chart = new Chart(this.el, {
      type: 'line',
      data: chartData,
      options: {
        responsive: true,
        maintainAspectRatio: false,
        plugins: {
          legend: {
            display: false // We have a custom legend in the header
          },
          tooltip: {
            mode: 'index',
            intersect: false,
            backgroundColor: 'rgba(0, 0, 0, 0.8)',
            padding: 12,
            titleFont: {
              size: 13
            },
            bodyFont: {
              size: 12
            },
            callbacks: {
              label: function(context) {
                let label = context.dataset.label || '';
                if (label) {
                  label += ': ';
                }
                if (context.parsed.y !== null) {
                  label += context.parsed.y.toFixed(1) + '%';
                }
                return label;
              }
            }
          }
        },
        scales: {
          y: {
            min: 0,
            max: 100,
            ticks: {
              stepSize: 25,
              callback: function(value) {
                return value + '%';
              }
            },
            grid: {
              color: 'rgba(0, 0, 0, 0.05)'
            }
          },
          x: {
            grid: {
              display: false
            },
            ticks: {
              maxTicksLimit: 14, // Show ~2 ticks per day for 7 days
              maxRotation: 0,
              autoSkip: true
            }
          }
        },
        interaction: {
          mode: 'nearest',
          axis: 'x',
          intersect: false
        },
        elements: {
          line: {
            tension: 0.3
          }
        }
      }
    });
  },

  updated() {
    if (!this.chart) return;

    const raw = this.el.dataset.chartData;
    if (!raw) return;

    try {
      const chartData = JSON.parse(raw);
      this.chart.data = chartData;
      this.chart.update('none');
    } catch (e) {
      console.error('HealthTrendChart: invalid updated chartData JSON', e);
    }
  },

  destroyed() {
    if (this.chart) {
      this.chart.destroy();
    }
  }
};
