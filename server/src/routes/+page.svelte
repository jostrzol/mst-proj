<script lang="ts">
	import { Chart } from 'chart.js';
	import { Checkbox } from 'svelte-ux';
	import { theme_color } from '$lib';
	import 'chartjs-adapter-date-fns';

	const SAMPLE_REFRESH_RATE = 20;
	const SAMPLE_INTERVAL_MS = 1000 / SAMPLE_REFRESH_RATE;

	interface Point {
		x: number;
		y: number;
	}

	let freqSet: Point[] = [];
	let freqRead: Point[] = [];
	let control: Point[] = [];

	let sample = $state(true);

	$effect(() => {
		const interval = setInterval(() => {
			if (sample) {
				const tMs = Date.now();
				const tS = tMs / 1000;
				const freqSetValue = ((Math.sin(tS) + 1) / 2) * 255;
				const freqReadValue = ((Math.cos(tS) + 1) / 2) * 255;
				const controlValue = ((Math.sin(tS + 1) + 1) / 2) * 255;

				freqSet.push({ x: tMs, y: freqSetValue });
				freqRead.push({ x: tMs, y: freqReadValue });
				control.push({ x: tMs, y: controlValue });
			}
			chart.update('quiet');
		}, SAMPLE_INTERVAL_MS);
		return () => clearInterval(interval);
	});

	let frequencyCanvas = $state<HTMLCanvasElement>(null!);
	let chart = $state<Chart>(null!);

	$effect(() => {
		const style = getComputedStyle(frequencyCanvas);
		const gridColor = theme_color(style, 'neutral');
		chart = new Chart(frequencyCanvas, {
			type: 'line',
			data: {
				datasets: [
					{
						label: 'Set frequency [Hz]',
						data: freqSet,
					},
					{
						label: 'Read frequency [Hz]',
						data: freqRead,
					},
				],
			},
			options: {
				clip: false,
				maintainAspectRatio: false,
				elements: {
					point: {
						pointStyle: false,
					},
				},
				scales: {
					y: {
						type: 'linear',
						grid: { color: gridColor },
						min: 0,
						max: 255,
					},
					x: {
						type: 'realtime',
						realtime: {
							duration: 20000,
							delay: 100,
						},
						grid: { color: gridColor },
					},
				},
				animation: false,
				animations: {
					colors: false,
					x: false,
				},
				transitions: {
					active: {
						animation: {
							duration: 0,
						},
					},
				},
			},
		});
		() => chart.destroy();
	});

	// let chartjsUpdate = $state(true);

	// $effect(() => {
	// 	if (chartjsUpdate) {
	// 		chart.data.labels = series[0].data.map(({ x }) => x);
	// 		chart.data.datasets[0].data = series[0].data.map(({ x, y }) => ({ x, y }));
	// 		chart.scales.x.ticks.min = xDomain[0] as any;
	// 		chart.scales.x.ticks.max = xDomain[1] as any;
	// 		// chart.scales['x'].min = xDomain[0];
	// 		// chart.scales['x'].max = xDomain[1];
	// 		// console.log(chart.scales['x'].min);
	// 		// console.log(chart);
	// 		chart.update('none');
	// 	}
	// });
</script>

<div class="m-4">
	<div class="flex gap-4 p-4">
		<label>
			Sample:
			<Checkbox bind:checked={sample} />
		</label>

		<!-- <label> -->
		<!-- 	Draw: -->
		<!-- 	<Checkbox bind:checked={draw} /> -->
		<!-- </label> -->

		<!-- <label> -->
		<!-- 	ChartJS update: -->
		<!-- 	<Checkbox bind:checked={chartjsUpdate} /> -->
		<!-- </label> -->

		<!-- <label> -->
		<!-- 	ChartJS update: -->
		<!-- 	<Button -->
		<!-- 		onclick={() => { -->
		<!-- 			chart.scales.x = { min: xDomain[0], max: xDomain[1], paddingRight: 0 }; -->
		<!-- 			chart.update('none'); -->
		<!-- 		}}>Update scales</Button -->
		<!-- 	> -->
		<!-- </label> -->
	</div>

	<div class="h-[300px] w-full rounded border p-4">
		<canvas bind:this={frequencyCanvas}></canvas>
	</div>
</div>
