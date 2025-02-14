<script lang="ts">
	import { Axis, Chart, Spline, Canvas, Legend } from 'layerchart';
	import { Checkbox } from 'svelte-ux';
	import { RingBuffer } from '$lib';
	import { scaleOrdinal } from 'd3-scale';
	import { untrack } from 'svelte';

	const SAMPLE_REFRESH_RATE = 20;
	const SAMPLE_INTERVAL_MS = 1000 / SAMPLE_REFRESH_RATE;

	const T_S_WINDOW = 8;
	const PTS_WINDOW = Math.ceil((T_S_WINDOW * 1000) / SAMPLE_INTERVAL_MS);

	let xsRaw = $state(new RingBuffer(Uint32Array, PTS_WINDOW));
	let y1sRaw = $state(new RingBuffer(Uint8Array, PTS_WINDOW));
	let y2sRaw = $state(new RingBuffer(Uint8Array, PTS_WINDOW));
	let tMsSample = $state(0);
	let tSSample = $derived(tMsSample / 1000);

	let sample = $state(true);

	$effect(() => {
		const interval = setInterval(() => {
			if (sample) {
				const y1 = ((Math.sin(tSSample) + 1) / 2) * 255;
				const y2 = ((Math.cos(tSSample) + 1) / 2) * 255;
				y1sRaw.push(y1);
				y2sRaw.push(y2);
				xsRaw.push(tMsSample);
			}
			tMsSample += SAMPLE_INTERVAL_MS;
		}, SAMPLE_INTERVAL_MS);
		return () => clearInterval(interval);
	});

	let xs = $state.raw(new Array<number>());
	let y1s = $state.raw(new Array<number>());
	let y2s = $state.raw(new Array<number>());
	let tMsDraw = $state(0);
	const tSDraw = $derived(tMsDraw / 1000);

	let draw = $state(true);

	$effect(() => {
		let frame = requestAnimationFrame(function loop() {
			if (draw) {
				xs = untrack(() => [...xsRaw]);
				y1s = untrack(() => [...y1sRaw]);
				y2s = untrack(() => [...y2sRaw]);
			}
			tMsDraw = untrack(() => tMsSample);
			frame = requestAnimationFrame(loop);
		});
		return () => cancelAnimationFrame(frame);
	});

	const xDomain = $derived([tSDraw - T_S_WINDOW, tSDraw]);

	const rawSeries = $derived([
		{ name: 'Read frequency [Hz]', rawData: y1s, color: 'red' },
		{ name: 'Set frequency [Hz]', rawData: y2s, color: 'green' },
	]);
	const series = $derived(
		rawSeries.map((series) => ({
			...series,
			data: [...series.rawData].map((value, i) => ({
				x: xs.at(i)! / 1000,
				y: value,
				c: series.name,
			})),
		})),
	);

	const combinedData = $derived(series.flatMap((series) => series.data));
</script>

<div class="m-4">
	<div class="flex gap-4 p-4">
		<label>
			Sample:
			<Checkbox bind:checked={sample} />
		</label>

		<label>
			Draw:
			<Checkbox bind:checked={draw} />
		</label>
	</div>

	<div class="h-[300px] rounded border p-4" role="img">
		<div class="h-full w-full overflow-hidden">
			<Chart
				data={combinedData}
				x="x"
				{xDomain}
				y="y"
				yDomain={[0, 255]}
				yNice
				c="c"
				cScale={scaleOrdinal()}
				cDomain={series.map(({ name }) => name)}
				cRange={series.map(({ color }) => color)}
				padding={{ left: 16, bottom: 48, right: 16 }}
				tooltip={{ mode: 'voronoi' }}
			>
				<Canvas>
					<Axis placement="left" grid rule />
					<Axis placement="bottom" rule />
					{#each series as { data, color }}
						<Spline {data} class="stroke-2" stroke={color}></Spline>
					{/each}
				</Canvas>
				<Legend placement="bottom" variant="swatches" />
			</Chart>
		</div>
	</div>
</div>
