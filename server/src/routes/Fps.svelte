<script lang="ts">
	import { scaleLinear } from 'd3-scale';
	import { untrack } from 'svelte';

	const SAMPLING_INTERVAL_MS = 1000;

	let frameIndexRaw = 0;

	$effect(() => {
		let frame = requestAnimationFrame(function loop() {
			frameIndexRaw += 1;
			frame = requestAnimationFrame(loop);
		});
		return () => cancelAnimationFrame(frame);
	});

	let frameIndex = $state(0);
	let lastFrameIndex = $state(0);
	$effect(() => {
		const interval = setInterval(() => {
			lastFrameIndex = frameIndex;
			frameIndex = frameIndexRaw;
		}, SAMPLING_INTERVAL_MS);
		return () => clearInterval(interval);
	});

	function hsl(color: string | undefined) {
		if (!color) return undefined;
		return `hsl(${color})`;
	}

	let p = $state<HTMLElement | undefined>();
	let color = $state(scaleLinear([0, 30, 60], ['red', 'yellow', 'green']).clamp(true));
	$effect(() => {
		const element = untrack(() => p);
		const style = getComputedStyle(element!);
		const colorError = hsl(style.getPropertyValue('--color-danger')) || 'red';
		const colorWarning = hsl(style.getPropertyValue('--color-warning')) || 'yellow';
		const colorSuccess = hsl(style.getPropertyValue('--color-success')) || 'green';
		color = scaleLinear([0, 30, 60], [colorError, colorWarning, colorSuccess]).clamp(true);
	});

	const fps = $derived(((frameIndex - lastFrameIndex) / SAMPLING_INTERVAL_MS) * 1000);
</script>

<div bind:this={p} class="inline-block w-fit">
	FPS: <span class="inline-block w-6 text-right" style:color={color(fps)}>{fps}</span>
</div>
