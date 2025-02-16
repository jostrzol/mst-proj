<script lang="ts">
	import { Checkbox } from 'svelte-ux';
	import LiveChart, { type Point } from './LiveChart.svelte';
	import 'chartjs-adapter-date-fns';

	const SAMPLE_REFRESH_RATE = 20;
	const SAMPLE_INTERVAL_MS = 1000 / SAMPLE_REFRESH_RATE;

	const freqSet: Point[] = $state([]);
	const freqRead: Point[] = $state([]);
	const control: Point[] = $state([]);

	let sample = $state(true);

	$effect(() => {
		const interval = setInterval(() => {
			if (sample) {
				const tMs = Date.now();
				const tS = tMs / 1000;
				const freqSetValue = ((Math.sin(tS) + 1) / 2) * 255;
				const freqReadValue = ((Math.cos(tS) + 1) / 2) * 255;
				const controlValue = ((Math.sin(tS + 1) + 1) / 2) * 255;

				freqSet.push({ x: tMs, y: freqSetValue });
				freqRead.push({ x: tMs, y: freqReadValue });
				control.push({ x: tMs, y: controlValue });
			}
		}, SAMPLE_INTERVAL_MS);
		return () => clearInterval(interval);
	});
</script>

<div class="m-4">
	<div class="flex gap-4 p-4">
		<label>
			Sample:
			<Checkbox bind:checked={sample} />
		</label>
	</div>

	<div class="flex flex-col gap-4">
		<LiveChart
			datasets={[
				{ label: 'Frequency set [Hz]', data: freqSet },
				{ label: 'Frequency read [Hz]', data: freqRead },
			]}
		/>

		<LiveChart datasets={[{ label: 'Control signal', data: control }]} />
	</div>
</div>
