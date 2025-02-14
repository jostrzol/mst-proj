<script lang="ts">
	import { Axis, Chart, Spline, Canvas, Legend } from 'layerchart';
	import { Checkbox } from 'svelte-ux';
	import { RingBuffer } from '$lib';
	import { scaleOrdinal } from 'd3-scale';
	import { untrack } from 'svelte';

	const SAMPLE_REFRESH_RATE = 20;
	const SAMPLE_BATCH_SIZE = 1;
	const SAMPLE_INTERVAL_MS = 1000 / SAMPLE_REFRESH_RATE;

	const T_S_WINDOW = 8;
	const PTS_WINDOW = Math.ceil((T_S_WINDOW * 1000) / SAMPLE_INTERVAL_MS);

	const tMsStart = Date.now();

	let xsRaw = new RingBuffer(Uint32Array, PTS_WINDOW);
	let y1sRaw = new RingBuffer(Uint8Array, PTS_WINDOW);
	let y2sRaw = new RingBuffer(Uint8Array, PTS_WINDOW);
	let y3sRaw = new RingBuffer(Uint8Array, PTS_WINDOW);

	let sample = $state(true);

	$effect(() => {
		const interval = setInterval(() => {
			if (sample) {
				const now = Date.now();
				const xsToAdd = [...Array(SAMPLE_BATCH_SIZE).keys()]
					.reverse()
					.map((i) => now - tMsStart - i * SAMPLE_INTERVAL_MS);
				const ys1ToAdd = xsToAdd.map((tMs) => ((Math.sin(tMs / 1000) + 1) / 2) * 255);
				const ys2ToAdd = xsToAdd.map((tMs) => ((Math.cos(tMs / 1000) + 1) / 2) * 255);
				const ys3ToAdd = xsToAdd.map((tMs) => ((Math.sin(tMs / 1000 + 1) + 1) / 2) * 255);

				y1sRaw.push(...ys1ToAdd);
				y2sRaw.push(...ys2ToAdd);
				y3sRaw.push(...ys3ToAdd);
				xsRaw.push(...xsToAdd);
			}
		}, SAMPLE_INTERVAL_MS * SAMPLE_BATCH_SIZE);
		return () => clearInterval(interval);
	});

	let xs = $state.raw(new Array<number>());
	let y1s = $state.raw(new Array<number>());
	let y2s = $state.raw(new Array<number>());
	let y3s = $state.raw(new Array<number>());

	let tMsDraw = $state(0);
	const tSDraw = $derived(tMsDraw / 1000);

	let draw = $state(true);

	$effect(() => {
		let frame = requestAnimationFrame(function loop() {
			if (draw) {
				xs = [...xsRaw];
				y1s = [...y1sRaw];
				y2s = [...y2sRaw];
				y3s = [...y3sRaw];
			}
			tMsDraw = Date.now() - tMsStart;
			frame = requestAnimationFrame(loop);
		});
		return () => cancelAnimationFrame(frame);
	});

	const xDomain = $derived([tSDraw - T_S_WINDOW, tSDraw]);

	const rawSeries = $derived([
		{ name: 'Read frequency [Hz]', rawData: y1s, color: 'red' },
		{ name: 'Set frequency [Hz]', rawData: y2s, color: 'green' },
		{ name: 'Control signal', rawData: y3s, color: 'yellow' },
	]);
	const series = $derived(
		rawSeries.map((series) => ({
			...series,
			data: series.rawData.map((value, i) => ({
				x: xs.at(i)! / 1000,
				y: value,
				c: series.name,
			})),
		})),
	);

	const frequencySeries = $derived(series.slice(0, 2));
	const controlSeries = $derived(series.slice(2, 3));
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

	{@render chart(frequencySeries)}

	{@render chart(controlSeries)}
</div>

{#snippet chart(localSeries: typeof series)}
	<div class="h-[300px] rounded border p-4" role="img">
		<div class="h-full w-full overflow-hidden">
			<Chart
				data={localSeries.flatMap(series => series.data)}
				x="x"
				{xDomain}
				y="y"
				yDomain={[0, 255]}
				yNice
				c="c"
				cScale={scaleOrdinal()}
				cDomain={localSeries.map(({ name }) => name)}
				cRange={localSeries.map(({ color }) => color)}
				padding={{ left: 16, bottom: 48, right: 16 }}
				tooltip={{ mode: 'voronoi' }}
			>
				<Canvas>
					<Axis placement="left" grid rule />
					<Axis placement="bottom" rule />
					{#each localSeries as { data, color }}
						<Spline {data} class="stroke-2" stroke={color}></Spline>
					{/each}
				</Canvas>

				<Legend placement="bottom" variant="swatches" />
			</Chart>
		</div>
	</div>
{/snippet}
