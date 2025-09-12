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
	import 'chartjs-adapter-date-fns';

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
	import { onMount } from 'svelte';

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

	export type Dataset = ChartDataset<'line', Point[]> & {
		stats?: { now?: boolean; average?: boolean };
	};

	export type DatasetProp = Dataset & {
		color?: string;
	};

	export interface Props {
		datasets: DatasetProp[];
		domain?: [number?, number?];
		realtime?: RealTimeScaleOptions['realtime'];
		yTitle?: string;
		isPaused?: boolean;
		crosshair?: { enabled?: boolean; color?: string };
		onclick?(point: Point): void;
	}

	const props: Props = $props();

	const [min = undefined, max = undefined] = props.domain || [];
	const { duration = 1000 * 10, delay = 0 } = props.realtime || {};
	const crosshair = props.crosshair || {};

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

	onMount(() => {
		const style = getComputedStyle(canvas);
		const gridColor = theme_color(style, 'neutral');
		chart = new Chart<'line', Point[], never>(canvas, {
			type: 'line',
			data: {
				datasets: $state.snapshot(datasets) as Dataset[],
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
				plugins: {
					legend: {
						labels: {
							filter: (item) => item.text != 'crosshair',
						},
					},
				},
			},
		});
		return () => chart?.destroy();
	});

	let yLine: number | undefined = $state(undefined);

	$effect(() => {
		if (!chart) return;

		let localDatasets = $state.snapshot(datasets) as Dataset[];
		if (yLine && crosshair.enabled)
			localDatasets.push({
				borderColor: crosshair.color,
				showLine: true,
				borderWidth: 1,
				data: [
					{ x: Date.now() - 60 * 60 * 1000, y: yLine },
					{ x: Date.now() + 60 * 60 * 1000, y: yLine },
				],
				label: 'crosshair',
			});

		chart.data.datasets = localDatasets;
		chart.options.plugins!.streaming!.pause = props.isPaused ?? false;
		chart.update();
	});

	const statsCurrent = $derived(
		datasets.map(({ borderColor, data, stats }) => {
			const endTimestamp = Date.now() - duration;
			let endIndex = data.findLastIndex((point) => point.x < endTimestamp);
			if (endIndex === -1) endIndex = data.length - 1;

			const values = data.slice(endIndex, data.length).map((point) => point.y);
			const now = values[values.length - 1] ?? 0;
			let average = values.reduce((acc, value) => acc + value, 0) / values.length;
			if (!isFinite(average)) average = 0;

			return {
				color: borderColor as string,
				now: stats?.now ? now : undefined,
				average: stats?.average ? average : undefined,
			};
		}),
	);
	let stats = $state<typeof statsCurrent>([]);
	$effect(() => {
		if (!props.isPaused) stats = statsCurrent;
	});

	function onclick(e: MouseEvent) {
		const point = getPoint(e);
		if (!point || !isPointInBounds(point)) return;

		props.onclick?.call(null, point);
	}

	function onmousemove(e: MouseEvent) {
		const point = getPoint(e);
		if (!point || !isPointInBounds(point)) {
			yLine = undefined;
			return;
		}

		yLine = point.y;
		if ((e.buttons & 1) == 0) return;

		props.onclick?.call(null, clampPointToBounds(point));
	}

	function onmouseleave(e: MouseEvent) {
		yLine = undefined;
		if ((e.buttons & 1) == 0) return;

		const point = getPoint(e);
		if (!point) return;

		props.onclick?.call(null, clampPointToBounds(point));
	}

	function clampPointToBounds(point: Point): Point {
		const bounds = getBounds();
		if (!bounds) return point;

		const { x, y } = point;
		const { xMin, xMax, yMin, yMax } = bounds;

		return {
			x: x < xMin ? xMin : x > xMax ? xMax : x,
			y: y < yMin ? yMin : y > yMax ? yMax : y,
		};
	}

	function isPointInBounds(point: Point): boolean {
		const bounds = getBounds();
		if (!bounds) return false;

		const { x, y } = point;
		const { xMin, xMax, yMin, yMax } = bounds;

		return x >= xMin && x <= xMax && y >= yMin && y <= yMax;
	}

	function getBounds(): { xMin: number; xMax: number; yMin: number; yMax: number } | undefined {
		if (!chart) return undefined;

		const { min: yMin, max: yMax } = chart?.scales.y.getMinMax(false) || { min: 0, max: 0 };
		const xMax = Date.now() - delay;
		const xMin = xMax - duration;
		return { xMin, xMax, yMin, yMax };
	}

	function getPoint(e: MouseEvent): Point | undefined {
		if (!chart) return undefined;

		const rect = canvas.getBoundingClientRect();
		const clientY = e.clientY - rect.top;
		const scaleY = chart.scales.y;
		const clientX = e.clientX - rect.left;
		const scaleX = chart.scales.x;
		const y = scaleY.getValueForPixel(clientY);
		const x = scaleX.getValueForPixel(clientX);
		if (x === undefined || y === undefined) return undefined;

		return { x, y };
	}

	function format(value: number) {
		const text = value.toFixed(2);
		const zerosLength = Math.max(5 - text.length, 0);
		const zeros = [...Array(zerosLength)].map(() => '0').join('');
		return zeros + text;
	}
</script>

<div class="flex h-[275px] w-full rounded border p-4">
	<div class="relative flex-grow">
		<canvas
			bind:this={canvas}
			onclick={crosshair.enabled ? onclick : null}
			onmousemove={crosshair.enabled ? onmousemove : null}
			onmouseleave={crosshair.enabled ? onmouseleave : null}
			style="position: absolute; width: 100%; height: 100%;"
		></canvas>
	</div>
	<aside class="align-center flex flex-col justify-center gap-2 p-4">
		{#each stats as stats}
			{#if stats.now !== undefined}{@render gauge('Now', stats.now, stats.color)}{/if}
			{#if stats.average !== undefined}{@render gauge('Avg.', stats.average, stats.color)}{/if}
		{/each}
	</aside>
</div>

{#snippet gauge(name: string, value: number, color: string)}
	<div class="relative m-1 w-20 rounded border" style:color>
		<span class="bg-surface-200 absolute -top-2 mx-1 px-1 text-xs">{name}</span>
		<div class="p-1 pt-2 text-center text-xl">{format(value)}</div>
	</div>
{/snippet}
