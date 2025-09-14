<script lang="ts">
	import { onMount } from 'svelte';
	import { Button, RangeField } from 'svelte-ux';
	import LiveChart, { type Point } from '$lib/components/LiveChart.svelte';
	import { faPlay, faPause } from '@fortawesome/free-solid-svg-icons';
	import { localJsonStorage } from '$lib/localJsonStorage';
	import { getSettings } from 'svelte-ux';
	import * as d3c from 'd3-color';
	import { Message } from '$lib/data/messages';
	import type { TuneParameters } from '$lib/components/TuneDials.svelte';
	import TuneDials from '$lib/components/TuneDials.svelte';
	import { slide } from 'svelte/transition';

	const { currentTheme, showDrawer } = getSettings();

	const PLOT_DURATION_MS = 6000;
	const PLOT_DELAY_MS = 200;

	const FREQ_RANGE: [number, number] = [0, 70];

	const SAMPLE_REFRESH_RATE = 20;
	const SAMPLE_INTERVAL_MS = 1000 / SAMPLE_REFRESH_RATE;

	const GC_INTERVAL_MS = 2 * PLOT_DURATION_MS;
	const GC_MAX_POINTS = GC_INTERVAL_MS / SAMPLE_INTERVAL_MS;

	const MS_PER_DAY = 24 * 60 * 60 * 1000;

	let targetControlSignal = $state(0);
	let parameters: TuneParameters = $state(
		localJsonStorage.get('tune-parameters') || {
			thresholdClose: 0.36,
			thresholdFar: 0.4,
		},
	);
	const { thresholdClose, thresholdFar } = $derived(parameters);

	const writeData = $derived({
		targetControlSignal,
		thresholdClose,
		thresholdFar,
	});

	$effect(() => {
		localJsonStorage.set('tune-parameters', parameters);
		const message = Message.serialize({ type: 'write', data: Object.values(writeData) });
		fetch('/sse', { method: 'POST', body: message });
	});

	let dataFrequency: Point[] = $state([]);
	let dataTargetControl: Point[] = $state([]);
	let dataCurrentControl: Point[] = $state([]);
	let dataValue: Point[] = $state([]);

	let eventSource: EventSource | undefined;
	onMount(() => {
		eventSource = new EventSource('/sse');
		eventSource.addEventListener('message', async (event) => {
			const message = Message.parse(event.data);
			if (message.type === 'read') {
				const timestamp = message.timestamp;
				const [frequency, controlSignal, valueMin, valueMax] = message.data;
				dataFrequency.push({ x: timestamp, y: frequency });
				dataCurrentControl.push({ x: timestamp, y: controlSignal });
				dataFrequency.push({ x: timestamp, y: frequency });
				dataValue.push({ x: timestamp, y: valueMin });
				dataValue.push({ x: timestamp, y: valueMax });
			} else if (message.type === 'connected' || message.type === 'recovered') {
				const data = Message.serialize({ type: 'write', data: Object.values(writeData) });
				fetch('/sse', { method: 'POST', body: data });
			} else console.error('Undefined SSE message:', message);
		});
		return () => eventSource?.close();
	});

	$effect(() => {
		const interval = setInterval(() => {
			if (!isPaused) {
				dataTargetControl = dataTargetControl.slice(-GC_MAX_POINTS);
				dataCurrentControl = dataCurrentControl.slice(-GC_MAX_POINTS);
				dataFrequency = dataFrequency.slice(-GC_MAX_POINTS);
				dataValue = dataValue.slice(-GC_MAX_POINTS);
			}
		}, GC_INTERVAL_MS);
		return () => clearInterval(interval);
	});

	let isPaused = $state(false);
	let togglePause = () => (isPaused = !isPaused);
	onMount(() => {
		const onKeyDown = (event: KeyboardEvent) => {
			if (event.key == ' ') {
				togglePause();
				event.preventDefault();
			}
		};
		window.addEventListener('keydown', onKeyDown);
		return () => window.removeEventListener('keydown', onKeyDown);
	});

	let controlColor = $derived($currentTheme.resolvedTheme === 'dark' ? 'yellow' : 'blue');
</script>

<div class="w-full p-4">
	<div class="flex flex-col gap-4">
		<LiveChart
			datasets={[
				{
					data: dataValue,
					color: 'olive',
					borderWidth: 1.5,
					stepped: 'before',
					stats: { now: true, average: true },
					segment: {
						borderColor: (ctx) => (ctx.p0.parsed.x === ctx.p1.parsed.x ? undefined : 'transparent'),
					},
				},
				{
					data: [
						{ x: Date.now() - 60 * 60 * 1000, y: thresholdClose },
						{ x: Date.now() + 60 * 60 * 1000, y: thresholdClose },
					],
					color: 'teal',
					borderWidth: 2,
				},
				{
					data: [
						{ x: Date.now() - 60 * 60 * 1000, y: thresholdFar },
						{ x: Date.now() + 60 * 60 * 1000, y: thresholdFar },
					],
					color: 'teal',
					borderWidth: 2,
				},
			]}
			realtime={{
				duration: PLOT_DURATION_MS,
				delay: PLOT_DELAY_MS,
			}}
			yTitle="ADC reading"
			{isPaused}
		/>

		<LiveChart
			datasets={[
				{
					data: dataFrequency,
					color: 'red',
					borderWidth: 1,
					stats: { now: true, average: true },
				},
			]}
			domain={FREQ_RANGE}
			realtime={{
				duration: PLOT_DURATION_MS,
				delay: PLOT_DELAY_MS,
			}}
			yTitle="Frequency [Hz]"
			{isPaused}
		/>

		<LiveChart
			onclick={({ y }) => (targetControlSignal = Math.round(y * 100) / 100)}
			datasets={[
				{
					label: 'Target',
					data: dataTargetControl,
					color: 'green',
					stepped: 'before',
					stats: { now: true, average: false },
				},
				{
					label: 'Current',
					data: dataCurrentControl,
					color: controlColor,
					borderWidth: 1,
					stats: { now: true, average: false },
				},
			]}
			domain={[0, 1]}
			realtime={{
				duration: PLOT_DURATION_MS,
				delay: PLOT_DELAY_MS,
			}}
			crosshair={{
				enabled: true,
				color: d3c.color('green')?.copy({ opacity: 0.5 }).toString(),
			}}
			yTitle="Control signal"
			{isPaused}
		/>
	</div>

	<div class="h-20"></div>

	{#if !$showDrawer}
		<div
			transition:slide
			class="bg-surface-100/90 fixed right-0 bottom-0 left-0 flex items-center justify-center gap-6 p-4"
		>
			<Button
				class="aspect-square w-10 cursor-pointer"
				variant="outline"
				icon={isPaused ? faPlay : faPause}
				onclick={togglePause}
			/>

			<RangeField
				value={targetControlSignal}
				on:change={({ detail: { value } }) => {
					const rounded = Math.round(value * 100) / 100;
					targetControlSignal = rounded;
					const now = Date.now();
					const point = { x: now, y: rounded };
					const cap = { x: now + MS_PER_DAY, y: rounded };
					dataTargetControl.pop();
					dataTargetControl.push(point, cap);
				}}
				label="Control signal"
				step={0.01}
				min={0.0}
				max={1.0}
			/>

			<TuneDials
				{parameters}
				onchange={(value) => {
					parameters = value;
				}}
			/>
		</div>
	{/if}
</div>
