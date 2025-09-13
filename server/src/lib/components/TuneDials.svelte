<script lang="ts">
	import { NumberStepper } from 'svelte-ux';

	export interface TuneParameters {
		tresholdClose: number;
		tresholdFar: number;
	}
	export interface Props {
		parameters: TuneParameters;
		onchange?(params: TuneParameters): void;
	}

	const { onchange, parameters }: Props = $props();
	const { tresholdClose, tresholdFar } = $derived(parameters);
</script>

<NumberStepper
	class="w-48"
	value={tresholdClose}
	min={0}
	max={tresholdFar}
	on:change={(e) => {
		let value = e.detail.value;
		if (value > tresholdFar) value = tresholdFar;

		onchange?.call(null, { ...parameters, tresholdClose: value });
	}}
	label="Treshold close"
	step={0.005}
/>

<NumberStepper
	class="w-48"
	value={tresholdFar}
	min={tresholdClose}
	max={1.0}
	on:change={(e) => {
		let value = e.detail.value;
		if (value < tresholdClose) value = tresholdClose;

		onchange?.call(null, { ...parameters, tresholdFar: value });
	}}
	label="Treshold far"
	step={0.005}
/>
