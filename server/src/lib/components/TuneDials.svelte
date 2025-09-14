<script lang="ts">
	import { NumberStepper } from 'svelte-ux';

	export interface TuneParameters {
		thresholdClose: number;
		thresholdFar: number;
	}
	export interface Props {
		parameters: TuneParameters;
		onchange?(params: TuneParameters): void;
	}

	const { onchange, parameters }: Props = $props();
	const { thresholdClose, thresholdFar } = $derived(parameters);
</script>

<NumberStepper
	class="w-48"
	value={thresholdClose}
	min={0}
	max={thresholdFar}
	on:change={(e) => {
		let value = e.detail.value;
		if (value > thresholdFar) value = thresholdFar;

		onchange?.call(null, { ...parameters, thresholdClose: value });
	}}
	label="Threshold close"
	step={0.005}
/>

<NumberStepper
	class="w-48"
	value={thresholdFar}
	min={thresholdClose}
	max={1.0}
	on:change={(e) => {
		let value = e.detail.value;
		if (value < thresholdClose) value = thresholdClose;

		onchange?.call(null, { ...parameters, thresholdFar: value });
	}}
	label="Threshold far"
	step={0.005}
/>
