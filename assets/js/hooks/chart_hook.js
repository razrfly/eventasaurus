import Chart from 'chart.js/auto';

export const ChartHook = {
  mounted() {
    console.log('ChartHook mounted!', this.el.id);
    console.log('Chart data:', this.el.dataset.chartData?.substring(0, 100));
    console.log('Chart available?', typeof Chart !== 'undefined');

    const chartData = JSON.parse(this.el.dataset.chartData);
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
  },

  updated() {
    if (this.chart) {
      const chartData = JSON.parse(this.el.dataset.chartData);
      this.chart.data = chartData;
      this.chart.update('none'); // Update without animation for smoother LiveView updates
    }
  },

  destroyed() {
    if (this.chart) {
      this.chart.destroy();
    }
  }
};
