<script lang="ts">
	import { Checkbox, NumberStepper } from 'svelte-ux';

	export interface PidParameters {
		proportionalFactor: number;
		integrationTime: number;
		differentiationTime: number;
	}
	export interface Props {
		parameters: PidParameters;
		onchange?(params: PidParameters): void;
	}

	const { onchange, parameters }: Props = $props();
	const { proportionalFactor, integrationTime, differentiationTime } = $derived(parameters);
</script>

<NumberStepper
	class="w-48"
	value={proportionalFactor}
	on:change={(e) => {
		onchange?.call(null, { ...parameters, proportionalFactor: e.detail.value });
	}}
	label="Proportional factor"
	step={0.01}
/>

<div class="flex flex-col gap-2">
	<NumberStepper
		class="w-48"
		value={integrationTime}
		disabled={!isFinite(integrationTime)}
		on:change={(e) => {
			onchange?.call(null, { ...parameters, integrationTime: e.detail.value });
		}}
		label="Integration time"
		step={0.01}
	/>
	<label>
		<Checkbox
			checked={!isFinite(integrationTime)}
			on:change={() => {
				const value = !isFinite(integrationTime) ? 1000 : Infinity;
				onchange?.call(null, { ...parameters, integrationTime: value });
			}}
		/>
		Infinity?
	</label>
</div>

<NumberStepper
	class="w-48"
	value={differentiationTime}
	on:change={(e) => {
		onchange?.call(null, { ...parameters, differentiationTime: e.detail.value });
	}}
	label="Differentiation time"
	step={0.01}
/>
