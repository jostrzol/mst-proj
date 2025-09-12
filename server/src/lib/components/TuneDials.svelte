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
	on:change={(e) => {
		onchange?.call(null, {
			...parameters,
			tresholdClose: e.detail.value,
		});
	}}
	label="Treshold close"
	step={0.005}
/>

<NumberStepper
	class="w-48"
	value={tresholdFar}
	on:change={(e) => {
		onchange?.call(null, {
			...parameters,
			tresholdFar: e.detail.value,
		});
	}}
	label="Treshold far"
	step={0.005}
/>
