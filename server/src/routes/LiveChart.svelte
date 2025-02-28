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
		Tooltip,
	} from 'chart.js';

	import ChartStreaming from 'chartjs-plugin-streaming';
	import 'chartjs-adapter-date-fns';

	Chart.register(
		Tooltip,
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
		domain?: [number?, number?];
		realtime?: RealTimeScaleOptions['realtime'];
		yTitle?: string;
		isPaused?: boolean;
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
				backgroundColor: borderColor?.darker(0.4).toString(),
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
				datasets: untrack(() => $state.snapshot(datasets)) as Dataset[],
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
						time: {
							displayFormats: {
								millisecond: 'HH:mm:ss.SSS',
								second: 'HH:mm:ss.SSS',
							},
						},
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
			chart.data.datasets = $state.snapshot(datasets) as Dataset[];
			chart.options.plugins!.streaming!.pause = props.isPaused ?? false;
			chart.update();
		}
	});

	function format(value: number) {
		const text = value.toFixed(2);
		const zerosLength = Math.max(5 - text.length, 0);
		const zeros = [...Array(zerosLength)].map(() => '0').join('');
		return zeros + text;
	}

	const datasetStats = $derived(
		datasets.map(({ borderColor, data }) => {
			const endTimestamp = Date.now() - (props.realtime?.duration || 1000 * 10);
			let endIndex = data.findLastIndex((point) => point.x < endTimestamp);
			if (endIndex === -1) endIndex = data.length - 1;

			const values = data.slice(endIndex, data.length).map((point) => point.y);
			const last = values[values.length - 1] ?? 0;
			let average = values.reduce((acc, value) => acc + value, 0) / values.length;
			if (!isFinite(average)) average = 0;

			return {
				color: borderColor as string,
				last: format(last),
				average: format(average),
			};
		}),
	);
</script>

<div class="flex h-[300px] w-full rounded border p-4">
	<div class="flex-grow">
		<canvas bind:this={canvas}></canvas>
	</div>
	<aside class="align-center flex flex-col justify-around p-4">
		{#each datasetStats as stats}
			<div class="flex flex-col text-center" style:color={stats.color}>
				<span>Now:</span>
				<span class="text-xl">{stats.last}</span>
				<span>Avg:</span>
				<span class="text-xl">{stats.average}</span>
			</div>
		{/each}
	</aside>
</div>
