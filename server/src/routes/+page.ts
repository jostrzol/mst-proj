import { CategoryScale, Chart, Colors, Legend, LinearScale, LineController, LineElement, PointElement } from 'chart.js';

import ChartStreaming from "chartjs-plugin-streaming"

Chart.register(
  Colors,
  LineController,
  LineElement,
  PointElement,
  CategoryScale,
  LinearScale,
  Legend,
  ChartStreaming
);
