import Chart from 'chart.js/auto';

export const ChartHook = {
  mounted() {
    console.log('ChartHook mounted!', this.el.id);
    console.log('Chart data:', this.el.dataset.chartData?.substring(0, 100));
    console.log('Chart available?', typeof Chart !== 'undefined');

    const raw = this.el.dataset.chartData;
    if (!raw) {
      console.warn('ChartHook: missing data-chart-data on', this.el.id);
      return;
    }

    let chartData;
    try {
      chartData = JSON.parse(raw);
    } catch (e) {
      console.error('ChartHook: invalid chartData JSON', e);
      return;
    }

    const chartType = this.el.dataset.chartType || 'line';

    console.log('Creating chart with type:', chartType, 'labels:', chartData.labels?.length);

    this.chart = new Chart(this.el, {
      type: chartType,
      data: chartData,
      options: {
        responsive: true,
        maintainAspectRatio: false,
        plugins: {
          legend: {
            display: chartData.datasets.length > 1,
            position: 'top',
          },
          tooltip: {
            mode: 'index',
            intersect: false,
          }
        },
        scales: chartType !== 'pie' && chartType !== 'doughnut' ? {
          y: {
            beginAtZero: true,
            ticks: {
              precision: 0
            }
          },
          x: {
            grid: {
              display: false
            }
          }
        } : undefined,
        interaction: {
          mode: 'nearest',
          axis: 'x',
          intersect: false
        }
      }
    });

    console.log('Chart created successfully!', this.el.id, this.chart);

    // Listen for chart update events from LiveView
    this.handleEvent("update-chart", ({chart_id, chart_data}) => {
      if (chart_id === this.el.id && this.chart) {
        console.log('Updating chart via event:', chart_id);
        this.chart.data = chart_data;
        this.chart.update('none'); // Update without animation
      }
    });
  },

  updated() {
    if (!this.chart) return;

    const raw = this.el.dataset.chartData;
    if (!raw) {
      console.warn('ChartHook: missing data-chart-data on update', this.el.id);
      return;
    }

    try {
      const chartData = JSON.parse(raw);
      this.chart.data = chartData;
      this.chart.update('none'); // Update without animation for smoother LiveView updates
    } catch (e) {
      console.error('ChartHook: invalid updated chartData JSON', e);
    }
  },

  destroyed() {
    if (this.chart) {
      this.chart.destroy();
    }
  }
};
