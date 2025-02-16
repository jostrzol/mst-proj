<script lang="ts">
	import { theme_color } from '$lib';
	import { interpolateRgbBasis } from 'd3-interpolate';
	import { scaleSequential } from 'd3-scale';

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

	let p = $state<HTMLElement>(null!);
	let colorInterpolator = $state(interpolateRgbBasis(['red', 'yellow', 'green']));
	let color = $derived(scaleSequential([0, 30, 60], colorInterpolator).clamp(true));
	$effect(() => {
		const style = getComputedStyle(p!);
		const colorError = theme_color(style, 'danger') || 'red';
		const colorWarning = theme_color(style, 'warning') || 'yellow';
		const colorSuccess = theme_color(style, 'success') || 'green';
		const colors = [colorError, colorWarning, colorSuccess];
		colorInterpolator = interpolateRgbBasis(colors);
	});

	const fps = $derived(((frameIndex - lastFrameIndex) / SAMPLING_INTERVAL_MS) * 1000);
</script>

<div bind:this={p} class="inline-block w-fit">
	FPS: <span class="inline-block w-6 text-right" style:color={color(fps)}>{fps}</span>
</div>
