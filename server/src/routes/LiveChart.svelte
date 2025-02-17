<script module lang="ts">
	import {
		CategoryScale,
		Chart,
		Colors,
		Legend,
		LinearScale,
		LineController,
		LineElement,
		PointElement,
	} from 'chart.js';

	import ChartStreaming from 'chartjs-plugin-streaming';

	Chart.register(
		Colors,
		LineController,
		LineElement,
		PointElement,
		CategoryScale,
		LinearScale,
		Legend,
		ChartStreaming,
	);
</script>

<script lang="ts">
	import { theme_color } from '$lib';
	import { type ChartDataset } from 'chart.js';
	import { untrack } from 'svelte';

	import 'chartjs-adapter-date-fns';
	import { pl } from 'date-fns/locale';
	import * as d3c from 'd3-color';
	import { scaleOrdinal } from 'd3-scale';
	import { schemeCategory10 } from 'd3-scale-chromatic';
	import type { RealTimeScaleOptions } from 'chartjs-plugin-streaming';

	export interface Point {
		x: number;
		y: number;
	}

	export type Dataset = ChartDataset<'line', Point[]>;

	export type DatasetProp = Dataset & {
		color?: string;
	};

	export interface Props {
		datasets: DatasetProp[];
		domain?: [number, number];
		realtime?: RealTimeScaleOptions['realtime'];
		yTitle?: string;
	}

	const props: Props = $props();
	const [min, max] = props.domain || [undefined, undefined];

	const scheme = scaleOrdinal(schemeCategory10);

	const datasets: Dataset[] = $derived(
		props.datasets.map(({ color, ...rest }, i) => {
			const colorIndex = i % schemeCategory10.length;
			const borderColor = d3c.color(color || scheme(colorIndex.toString()));
			return {
				borderColor: borderColor?.toString(),
				backgroundColor: borderColor?.copy({ opacity: 0.6 }).toString(),
				...rest,
			};
		}),
	);

	let canvas = $state<HTMLCanvasElement>(null!);
	let chart = $state<Chart>();

	$effect(() => {
		const style = getComputedStyle(canvas);
		const gridColor = theme_color(style, 'neutral');
		chart = new Chart<'line', Point[], never>(canvas, {
			type: 'line',
			data: {
				datasets: untrack(() => $state.snapshot(datasets)) as any,
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
						min,
						max,
						title: { text: props.yTitle, display: !!props.yTitle },
					},
					x: {
						type: 'realtime',
						realtime: props.realtime,
						grid: { color: gridColor },
						adapters: { date: { locale: pl } },
						title: { text: 'Time', display: true },
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
				locale: 'pl-PL',
			},
		});
		return () => chart?.destroy();
	});

	$effect(() => {
		if (chart) {
			chart.data.datasets = $state.snapshot(datasets) as any;
			chart.update();
		}
	});
</script>

<div class="h-[300px] w-full rounded border p-4">
	<canvas bind:this={canvas}></canvas>
</div>
