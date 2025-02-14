<script lang="ts">
	import { scaleLinear, scaleSequential } from 'd3-scale';
	import { interpolateRgb, interpolateRgbBasis } from 'd3-interpolate';
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
		return `hsl(${color.split(' ').join(',')})`;
	}

	let p = $state<HTMLElement | undefined>();
	let colorInterpolator = $state(interpolateRgbBasis(['red', 'yellow', 'green']));
	let color = $derived(scaleSequential([0, 30, 60], colorInterpolator).clamp(true));
	$effect(() => {
		const element = untrack(() => p);
		const style = getComputedStyle(element!);
		const colorError = hsl(style.getPropertyValue('--color-danger')) || 'red';
		const colorWarning = hsl(style.getPropertyValue('--color-warning')) || 'yellow';
		const colorSuccess = hsl(style.getPropertyValue('--color-success')) || 'green';
		const colors = [colorError, colorWarning, colorSuccess];
		colorInterpolator = interpolateRgbBasis(colors);
	});

	const fps = $derived(((frameIndex - lastFrameIndex) / SAMPLING_INTERVAL_MS) * 1000);
</script>

<div bind:this={p} class="inline-block w-fit">
	FPS: <span class="inline-block w-6 text-right" style:color={color(fps)}>{fps}</span>
</div>
