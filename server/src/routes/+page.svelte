<script lang="ts">
  import { ThemeSwitch } from "svelte-ux";
	import { LineChart } from 'layerchart';
	import { ticks } from 'd3-array';

	let dynamicData = ticks(-2, 2, 200).map(Math.sin);

	let renderContext: 'svg' | 'canvas' = 'svg';
	let debug = false;
</script>

<ThemeSwitch />

<h2>Dynamic data (move over chart)</h2>

<!-- svelte-ignore a11y-no-static-element-interactions -->
<div
	class="h-[300px] rounded border p-4"
	on:mousemove={(e) => {
		const x = e.clientX;
		const y = e.clientY;
		dynamicData = dynamicData.slice(-200).concat(Math.atan2(x, y));
	}}
>
	<LineChart
		data={dynamicData.map((d, i) => ({ x: i, y: d }))}
		x="x"
		y="y"
		yBaseline={undefined}
		tooltip={{ mode: 'manual' }}
		props={{ yAxis: { tweened: true }, grid: { tweened: true } }}
		{renderContext}
		{debug}
	/>
</div>

<h2>Brushing</h2>

<div class="h-[300px] rounded border p-4">
	<LineChart
		data={dynamicData}
		x="date"
		y="value"
		brush
		props={{
			spline: { tweened: { duration: 200 } },
			xAxis: { format: undefined, tweened: { duration: 200 } }
		}}
		{renderContext}
		{debug}
	/>
</div>
