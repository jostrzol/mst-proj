<script lang="ts">
	import { Checkbox, NumberStepper } from 'svelte-ux';

	interface Props {
		proportionalFactor?: number;
		integrationTime?: number;
		differentiationTime?: number;
	}

	let {
		proportionalFactor = $bindable(0),
		integrationTime = $bindable(Infinity),
		differentiationTime = $bindable(0),
	}: Props = $props();
</script>

<NumberStepper
	class="w-48"
	bind:value={proportionalFactor}
	label="Proportional factor"
	step={0.01}
/>

<div class="flex flex-col gap-2">
	<NumberStepper
		class="w-48"
		value={integrationTime}
		disabled={!isFinite(integrationTime)}
		on:change={(event) => (integrationTime = event.detail.value)}
		label="Integration time"
		step={0.01}
	/>
	<label>
		<Checkbox
			checked={!isFinite(integrationTime)}
			on:change={() => {
				integrationTime = !isFinite(integrationTime) ? 1000 : Infinity;
			}}
		/>
		Infinity?
	</label>
</div>

<NumberStepper
	class="w-48"
	bind:value={differentiationTime}
	label="Differentiation time"
	step={0.01}
/>
