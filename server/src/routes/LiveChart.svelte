<script lang="ts">
	import { Chart } from 'chart.js';
	import { theme_color } from '$lib';
	import { untrack } from 'svelte';

	import 'chartjs-adapter-date-fns';

	export interface Point {
		x: number;
		y: number;
	}

	interface Props {
		datasets: {
			label: string;
			data: Point[];
		}[];
	}

	let { datasets }: Props = $props();

	let canvas = $state<HTMLCanvasElement>(null!);
	let chart = $state<Chart>();

	$effect(() => {
		const style = getComputedStyle(canvas);
		const gridColor = theme_color(style, 'neutral');
		chart = new Chart(canvas, {
			type: 'line',
			data: {
				datasets: untrack(() => $state.snapshot(datasets)),
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
		return () => chart?.destroy();
	});

	$effect(() => {
		if (chart) {
			chart.data.datasets = $state.snapshot(datasets);
			chart.update();
		}
	});
</script>

<div class="h-[300px] w-full rounded border p-4">
	<canvas bind:this={canvas}></canvas>
</div>
