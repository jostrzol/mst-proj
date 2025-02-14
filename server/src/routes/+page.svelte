<script lang="ts">
	import { LineChart } from 'layerchart';
	import { Checkbox } from 'svelte-ux';
	import { RingBuffer } from '$lib';

	const REFRESH_RATE = 60;
	const INTERVAL_MS = 1000 / REFRESH_RATE;
	const T_S_WINDOW = 8;
	const PTS_WINDOW = Math.ceil((T_S_WINDOW * 1000) / INTERVAL_MS);

	let draw = $state(true);

	let t_ms = $state(0);
	const t_s = $derived(t_ms / 1000);

	let xs = $state(new RingBuffer(Uint32Array, PTS_WINDOW));
	let ys = $state(new RingBuffer(Uint8Array, PTS_WINDOW));

	$effect(() => {
		const interval = setInterval(() => {
			if (draw) {
				const y = ((Math.sin(t_s) + 1) / 2) * 255;
				ys.push(y);
				xs.push(t_ms);
			}
			t_ms += INTERVAL_MS;
		}, INTERVAL_MS);
		return () => clearInterval(interval);
	});

	const xDomain = $derived([t_s - T_S_WINDOW, t_s]);

	const plotData = $derived([...ys].map((value, i) => ({ x: xs.at(i)! / 1000, y: value })));
</script>

<h2>Dynamic data (move over chart)</h2>

<Checkbox bind:checked={draw} />

<div class="h-[300px] rounded border p-4" role="img">
	<div class="h-full w-full overflow-hidden">
		<LineChart
			data={plotData}
			x="x"
			y="y"
			yDomain={[0, 255]}
			{xDomain}
			tooltip={{ mode: 'manual' }}
			props={{ yAxis: { tweened: true }, grid: { tweened: true } }}
			renderContext="canvas"
			debug={false}
		/>
	</div>
</div>

<!-- <h2>Brushing</h2> -->

<!-- <div class="h-[300px] rounded border p-4"> -->
<!-- 	<LineChart -->
<!-- 		{data} -->
<!-- 		x="date" -->
<!-- 		y="value" -->
<!-- 		brush -->
<!-- 		props={{ -->
<!-- 			spline: { tweened: { duration: 200 } }, -->
<!-- 			xAxis: { format: undefined, tweened: { duration: 200 } }, -->
<!-- 		}} -->
<!-- 		renderContext="svg" -->
<!-- 		debug={false} -->
<!-- 	/> -->
<!-- </div> -->
