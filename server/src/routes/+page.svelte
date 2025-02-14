<script lang="ts">
	import { map } from 'd3-array';
	import { LineChart } from 'layerchart';
	import { onMount } from 'svelte';
	import { Checkbox } from 'svelte-ux';

	const REFRESH_RATE = 60;
	const INTERVAL_MS = 1000 / REFRESH_RATE;
	const T_S_WINDOW = 8;
	const PTS_WINDOW = Math.ceil((T_S_WINDOW * 1000) / INTERVAL_MS);

	let draw = $state(true);

	let t_ms = $state(0);
	const t_s = $derived(t_ms / 1000);

	let xs = $state.raw(new Uint32Array(PTS_WINDOW));
	let ys = $state.raw(new Uint8Array(PTS_WINDOW));

	$effect(() => {
		const interval = setInterval(() => {
			if (draw) {
				const y = ((Math.sin(t_s) + 1) / 2) * 255;
				ys = new Uint8Array([...ys.slice(-PTS_WINDOW - 1), y]);
				xs = new Uint32Array([...xs.slice(-PTS_WINDOW - 1), t_ms]);
			}
			t_ms += INTERVAL_MS;
		}, INTERVAL_MS);
		return () => clearInterval(interval);
	});

	const xDomain = $derived([t_s - T_S_WINDOW, t_s]);

	// const plotData = $derived.by(() => {
	// 	let last: Point = { x: Infinity, y: Infinity };
	// 	let result: Point[] = [];

	// 	for (let i = data.length - 1; i >= 0; i--) {
	// 		const point = data[i];
	// 		const { x } = point;

	// 		if (x > xDomain[1]) continue;
	// 		if (Math.abs(last.x - point.x) < T_S_RESOLUTION) continue;
	// 		if (x < xDomain[0]) break;

	// 		result.push(point);
	// 		last = point;
	// 	}

	// 	return result;
	// });
	// let plotData: Point[] = $state.raw([]);
	// onMount(() => {
	// 	let frame: number;

	// 	const loop = () => {
	// 		let last: Point = { x: Infinity, y: Infinity };
	// 		let result: Point[] = [];

	// 		for (let i = data.length - 1; i >= 0; i--) {
	// 			const point = data[i];
	// 			const { x } = point;

	// 			if (x > xDomain[1]) continue;

	// 			const dT = Math.abs(last.x - point.x);
	// 			const isLast = x < xDomain[0];
	// 			if (dT < T_S_RESOLUTION && !isLast) continue;

	// 			result.push(point);
	// 			last = point;

	// 			if (isLast) break;
	// 		}

	// 		frame = requestAnimationFrame(loop);
	// 		plotData = result;
	// 	};

	// 	frame = requestAnimationFrame(loop);

	// 	return () => cancelAnimationFrame(frame);
	// });

	const plotData = $derived([...ys].map((value, i) => ({ x: xs[i] / 1000, y: value })));
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
