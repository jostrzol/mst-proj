<script lang="ts">
	import { onMount } from 'svelte';
	import { Checkbox, RangeField } from 'svelte-ux';
	import LiveChart, { type Point } from './LiveChart.svelte';
	import type { Reading } from '$lib/server';

	const PLOT_DURATION_MS = 20000;
	const PLOT_DELAY_MS = 200;

	const FREQ_RANGE: [number, number] = [0, 1000];
	const [FREQ_MIN, FREQ_MAX] = FREQ_RANGE;

	const SAMPLE_REFRESH_RATE = 20;
	const SAMPLE_INTERVAL_MS = 1000 / SAMPLE_REFRESH_RATE;

	const GC_INTERVAL_MS = 20 * 1000;
	const GC_MAX_POINTS = (PLOT_DURATION_MS / SAMPLE_INTERVAL_MS) * 2;

	const MS_PER_DAY = 24 * 60 * 60 * 1000;

	let freqTarget: Point[] = $state([]);
	let freqCurrent: Point[] = $state([]);
	let control: Point[] = $state([]);

	let sample = $state(true);
	onMount(() => {
		const socket = new WebSocket(`/ws`);
		socket.addEventListener('message', async (event: MessageEvent<string>) => {
      console.log(event.data)
      const data = JSON.parse(event.data) as Reading[]
			const points = data.map(({ value, timestamp }) => ({ x: timestamp, y: value / 255 * 1000 }));
			freqCurrent.push(...points);
		});
	});

	$effect(() => {
		const interval = setInterval(() => {
			if (sample) {
				const tMs = Date.now();
				const tS = tMs / 1000;
				const controlValue = (Math.sin(tS + 1) + 1) / 2;

				control.push({ x: tMs, y: controlValue });
			}
		}, SAMPLE_INTERVAL_MS);
		return () => clearInterval(interval);
	});

	$effect(() => {
		const interval = setInterval(() => {
			freqTarget = freqTarget.slice(-GC_MAX_POINTS);
			freqCurrent = freqCurrent.slice(-GC_MAX_POINTS);
			control = control.slice(-GC_MAX_POINTS);
		}, GC_INTERVAL_MS);
		return () => clearInterval(interval);
	});
</script>

<div class="m-4">
	<div class="flex gap-4 p-4">
		<Checkbox bind:checked={sample}>Sample</Checkbox>

		<RangeField
			on:change={({ detail: { value } }) => {
				const now = Date.now();
				const point = { x: now, y: value };
				const cap = { x: now + MS_PER_DAY, y: value };
				freqTarget.pop();
				freqTarget.push(point, cap);
			}}
			label="Target frequency [Hz]"
			min={FREQ_MIN}
			max={FREQ_MAX}
		/>
	</div>

	<div class="flex flex-col gap-4">
		<LiveChart
			datasets={[
				{ label: 'Target', data: freqTarget, color: 'green', stepped: 'before' },
				{ label: 'Current', data: freqCurrent, color: 'red' },
			]}
			domain={FREQ_RANGE}
			realtime={{
				duration: PLOT_DURATION_MS,
				delay: PLOT_DELAY_MS,
			}}
			yTitle="Frequency [Hz]"
		/>

		<LiveChart
			datasets={[{ label: 'Control signal', data: control, color: 'yellow' }]}
			domain={[0, 1]}
			realtime={{
				duration: PLOT_DURATION_MS,
				delay: PLOT_DELAY_MS,
			}}
			yTitle="Duty cycle"
		/>
	</div>
</div>
