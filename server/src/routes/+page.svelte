<script lang="ts">
	import { onMount } from 'svelte';
	import { Button, RangeField } from 'svelte-ux';
	import LiveChart, { type Point } from './LiveChart.svelte';
	import { faPlay, faPause } from '@fortawesome/free-solid-svg-icons';
	import { WsMessage } from './ws/messages';
	import type { PidParameters } from './PidParametersDial.svelte';
	import PidParametersDial from './PidParametersDial.svelte';
	import { localJsonStorage } from '$lib/localJsonStorage';
	import { getSettings } from 'svelte-ux';

	const { currentTheme } = getSettings();

	const PLOT_DURATION_MS = 4000;
	const PLOT_DELAY_MS = 200;

	const FREQ_RANGE: [number?, number?] = [0, 70];
	const [FREQ_MIN, FREQ_MAX] = FREQ_RANGE;

	const SAMPLE_REFRESH_RATE = 20;
	const SAMPLE_INTERVAL_MS = 1000 / SAMPLE_REFRESH_RATE;

	const GC_INTERVAL_MS = 2 * PLOT_DURATION_MS;
	const GC_MAX_POINTS = GC_INTERVAL_MS / SAMPLE_INTERVAL_MS;

	const MS_PER_DAY = 24 * 60 * 60 * 1000;

	let targetFrequency = $state(0);
	let parameters: PidParameters = $state(
		localJsonStorage.get('pid-parameters') || {
			proportionalFactor: 0,
			integrationTime: Infinity,
			differentiationTime: 0,
		},
	);

	const writeData = $derived({ targetFrequency, ...parameters });

	$effect(() => {
		localJsonStorage.set('pid-parameters', parameters);
		const message = WsMessage.serialize({ type: 'write', data: writeData });
		socket?.send(message);
	});

	let dataTarget: Point[] = $state([]);
	let dataCurrent: Point[] = $state([]);
	let dataControl: Point[] = $state([]);

	let socket: WebSocket | undefined;
	onMount(() => {
		socket = new WebSocket(`/ws`);
		socket.addEventListener('message', async (event: MessageEvent<string>) => {
			const message = WsMessage.parse(event.data);
			if (message.type === 'read') {
				const reading = message.data;
				dataCurrent.push({ x: reading.timestamp, y: reading.frequency });
				dataControl.push({ x: reading.timestamp, y: reading.controlSignal });
			} else if (message.type === 'connected' || message.type === 'recovered') {
				socket!.send(WsMessage.serialize({ type: 'write', data: writeData }));
			} else console.error('Undefined WS message:', message);
		});
		return socket.close;
	});

	$effect(() => {
		const interval = setInterval(() => {
			if (!isPaused) {
				dataTarget = dataTarget.slice(-GC_MAX_POINTS);
				dataCurrent = dataCurrent.slice(-GC_MAX_POINTS);
				dataControl = dataControl.slice(-GC_MAX_POINTS);
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
</script>

<div class="m-4">
	<div class="flex gap-4 p-4">
		<div class="aspect-square">
			<Button
				variant="outline"
				color="primary"
				icon={isPaused ? faPlay : faPause}
				onclick={togglePause}
			/>
		</div>

		<RangeField
			bind:value={targetFrequency}
			on:change={({ detail: { value } }) => {
				const now = Date.now();
				const point = { x: now, y: value };
				const cap = { x: now + MS_PER_DAY, y: value };
				dataTarget.pop();
				dataTarget.push(point, cap);
			}}
			label="Target frequency [Hz]"
			min={FREQ_MIN}
			max={FREQ_MAX}
		/>

		<PidParametersDial
			{parameters}
			onchange={(value) => {
				parameters = value;
			}}
		/>
	</div>

	<div class="flex flex-col gap-4">
		<LiveChart
			datasets={[
				{
					label: 'Target',
					data: dataTarget,
					color: 'green',
					stepped: 'before',
					stats: { now: true, average: false },
				},
				{
					label: 'Current',
					data: dataCurrent,
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
			datasets={[
				{
					label: 'Control signal',
					data: dataControl,
					color: $currentTheme.resolvedTheme === 'dark' ? 'yellow' : 'blue',
					stats: { now: true, average: true },
				},
			]}
			domain={[0, 1]}
			realtime={{
				duration: PLOT_DURATION_MS,
				delay: PLOT_DELAY_MS,
			}}
			yTitle="Duty cycle"
			{isPaused}
		/>
	</div>
</div>
